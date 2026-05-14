import Foundation
import SwiftData
import WatchConnectivity

/// Central coordinator: reads medications from SwiftData, schedules notifications
/// and AlarmPlayer entries, manages the alarm lifecycle.
final class NagScheduler {
    static let shared = NagScheduler()

    private var modelContainer: ModelContainer?
    private var dailySyncTimer: Timer?

    private init() {}

    /// Must be called once after the model container is ready.
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        startDailySyncTimer()
    }

    // MARK: - Sync

    /// Full reschedule: cancel all notifications, then schedule for all enabled medications.
    @MainActor
    func sync() async {
        guard let container = modelContainer else {
            print("[NagRX] NagScheduler: no model container configured")
            return
        }

        NotificationService.shared.cancelAll()
        AlarmPlayer.shared.stopPlayback()

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\Medication.scheduledHour)]
        )

        guard let medications = try? context.fetch(descriptor) else {
            print("[NagRX] NagScheduler: failed to fetch medications")
            return
        }

        // Notification budget: iOS allows 64 pending notifications.
        // Maximize re-nags per medication so alerts keep firing until dismissed.
        let medCount = max(medications.count, 1)

        var alarmEntries: [AlarmPlayer.Entry] = []
        var activeNames: [String] = []
        let intervalSeconds = Double(AppSettings.shared.reNagIntervalMinutes) * 60

        // Budget per medication: fill up to 64 total notifications across all meds.
        // Each medication gets 1 upcoming occurrence, rest of budget goes to re-nags.
        let reNagsPerMed = max((64 / medCount) - 1, 5)

        for med in medications {
            let upcomingDates = med.nextFireDates(limit: 1)

            for (index, fireDate) in upcomingDates.enumerated() {
                let identifier = "\(med.notificationIdentifier)_occ\(index)"

                await NotificationService.shared.scheduleAlarm(
                    identifier: identifier,
                    medicationName: med.name,
                    fireDate: fireDate,
                    sound: med.sound,
                    reNagCount: med.silentReminder ? 0 : reNagsPerMed,
                    silentReminder: med.silentReminder
                )

                // Silent reminders don't need AlarmPlayer entries
                if !med.silentReminder {
                    let entryFireDates = (0...reNagsPerMed).compactMap { i -> Date? in
                        let date = fireDate.addingTimeInterval(Double(i) * intervalSeconds)
                        return date > Date() ? date : nil
                    }

                    if !entryFireDates.isEmpty {
                        alarmEntries.append(AlarmPlayer.Entry(
                            identifier: identifier,
                            fireDates: entryFireDates,
                            sound: med.sound,
                            medicationName: med.name
                        ))
                    }
                }
            }

            // Check if any alarm for this medication is currently active (no time limit)
            if !med.silentReminder {
                let nextFire = med.nextFireDate
                if nextFire <= Date() {
                    activeNames.append(med.name)
                }
            }
        }

        AlarmPlayer.shared.setSchedule(alarmEntries)

        // Update widget shared state
        SharedState.activeMedicationNames = activeNames
        SharedState.hasActiveAlarm = !activeNames.isEmpty

        // Sync medication list to Apple Watch
        sendMedicationsToWatch(from: container)
    }

    /// Schedule a single medication (called when adding a new one without full resync).
    @MainActor
    func scheduleMedication(_ med: Medication) async {
        let fireDates = med.nextFireDates(limit: 1)
        for (index, fireDate) in fireDates.enumerated() {
            let identifier = "\(med.notificationIdentifier)_occ\(index)"
            await NotificationService.shared.scheduleAlarm(
                identifier: identifier,
                medicationName: med.name,
                fireDate: fireDate,
                sound: med.sound
            )
        }
    }

    /// Cancel alarms for a specific medication (called when deleting or disabling).
    func cancelMedication(_ med: Medication) {
        let baseId = med.notificationIdentifier
        var identifiers: [String] = []
        for i in 0..<10 {
            identifiers.append("\(baseId)_occ\(i)")
        }
        NotificationService.shared.cancel(identifiers: identifiers)
        for id in identifiers {
            AlarmPlayer.shared.dismiss(identifier: id)
        }
    }

    // MARK: - Watch Sync

    /// Sends the current medication list to the Apple Watch via WatchConnectivity.
    private func sendMedicationsToWatch(from container: ModelContainer) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            print("[NagRX] Watch sync skipped: session not activated (state: \(session.activationState.rawValue))")
            return
        }

        #if os(iOS)
        guard session.isPaired else {
            print("[NagRX] Watch sync skipped: no Watch paired")
            return
        }
        guard session.isWatchAppInstalled else {
            print("[NagRX] Watch sync skipped: Watch app not installed")
            return
        }
        #endif

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Medication>(
            sortBy: [SortDescriptor(\Medication.scheduledHour)]
        )

        guard let allMeds = try? context.fetch(descriptor) else {
            print("[NagRX] Watch sync failed: could not fetch medications")
            return
        }

        struct WatchMed: Codable {
            let id: UUID
            let name: String
            let scheduledHour: Int
            let scheduledMinute: Int
            let isEnabled: Bool
            let formattedSchedule: String
            let nextFireDateTimestamp: TimeInterval
        }

        let watchMeds = allMeds.map { med in
            WatchMed(
                id: med.id,
                name: med.name,
                scheduledHour: med.scheduledHour,
                scheduledMinute: med.scheduledMinute,
                isEnabled: med.isEnabled,
                formattedSchedule: med.formattedSchedule,
                nextFireDateTimestamp: med.nextFireDate.timeIntervalSince1970
            )
        }

        guard let data = try? JSONEncoder().encode(watchMeds) else {
            print("[NagRX] Watch sync failed: could not encode medications")
            return
        }

        let reNagMinutes = AppSettings.shared.reNagIntervalMinutes
        let payload: [String: Any] = [
            "medications": data,
            "reNagIntervalMinutes": reNagMinutes
        ]

        print("[NagRX] Sending \(watchMeds.count) medications to Watch (reNag: \(reNagMinutes)min, reachable: \(session.isReachable))")

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[NagRX] sendMessage failed: \(error), falling back to transferUserInfo")
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    // MARK: - Daily Sync Timer

    /// Re-schedules alarms daily at midnight so tomorrow's fire dates are always queued.
    private func startDailySyncTimer() {
        guard dailySyncTimer == nil else { return }

        let cal = Calendar.current
        var midnightComps = cal.dateComponents([.year, .month, .day], from: Date())
        midnightComps.hour = 0
        midnightComps.minute = 1
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.date(from: midnightComps) ?? Date()) else { return }

        let interval = tomorrow.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + max(interval, 60)) { [weak self] in
            Task { @MainActor in
                await self?.sync()
            }
            self?.dailySyncTimer = nil
            self?.startDailySyncTimer()
        }
    }
}
