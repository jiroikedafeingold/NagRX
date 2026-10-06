import Foundation
import SwiftData
import WatchConnectivity
import BackgroundTasks

/// Central coordinator: reads medications from SwiftData and schedules a system
/// alarm (AlarmKit) for each dose, with re-alerts at the configured interval until
/// the dose is taken. Falls back to notifications when alarms aren't allowed.
final class NagScheduler {
    static let shared = NagScheduler()

    /// Background refresh identifier — must match Info.plist BGTaskSchedulerPermittedIdentifiers.
    static let refreshTaskID = "com.jirofeingold.NagRX.refresh"

    /// Doses booked ahead per medication. Alarms ring without NagRX running, so
    /// booking a few lets tomorrow's dose ring even if the app isn't opened.
    private static let dosesAhead = 3

    private var modelContainer: ModelContainer?

    /// The last payload handed to WatchConnectivity. sync() runs on every
    /// foreground and transferUserInfo queues a Bluetooth transfer even when the
    /// Watch is out of range, so unchanged lists used to pile up as radio work.
    private var lastWatchPayload: Data?

    private init() {}

    /// Forget the last payload so the next sync() sends to the Watch regardless.
    /// Used when the Watch itself asks for data (fresh install, lost state).
    func invalidateWatchPayloadCache() {
        lastWatchPayload = nil
    }

    /// Must be called once after the model container is ready.
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Sync

    /// Rebuilds every dose alarm (or fallback notification) from the medication list.
    @MainActor
    func sync() async {
        guard let container = modelContainer else {
            print("[NagRX] NagScheduler: no model container configured")
            return
        }

        NotificationService.shared.cancelAllPending()
        NotificationService.shared.tidyDeliveredNotifications()

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\Medication.scheduledHour)]
        )
        guard let medications = try? context.fetch(descriptor) else {
            print("[NagRX] NagScheduler: failed to fetch medications")
            return
        }

        let now = Date()
        let alarms = DoseAlarms.shared
        let useAlarms = alarms.isAuthorized
        let intervalSeconds = Double(AppSettings.shared.reNagIntervalMinutes) * 60

        // Re-alert budget per medication — unchanged from the notification
        // version, so a missed dose nags for just as long as it always did.
        let medCount = max(medications.count, 1)
        let reNagsPerMed = max((64 / medCount) - 1, 5)
        let nagSpan = Double(reNagsPerMed) * intervalSeconds

        var requests: [DoseAlarmRequest] = []
        var doses: [SharedState.Dose] = []

        for med in medications {
            let medID = med.id.uuidString

            if med.silentReminder {
                // Silent reminders stay a single quiet notification.
                if let next = med.nextFireDates(limit: 1).first {
                    await NotificationService.shared.scheduleAlarm(
                        identifier: "\(med.notificationIdentifier)_occ0",
                        medicationName: med.name,
                        fireDate: next,
                        sound: med.sound,
                        reNagCount: 0,
                        silentReminder: true,
                        medicationID: medID
                    )
                }
                continue
            }

            // A dose that's already due, not yet taken, and still inside its
            // nagging window keeps nagging — only if NagRX actually alarmed for it.
            let lookBack = now.addingTimeInterval(-(nagSpan + Double(DoseAlarms.snoozeMinutes) * 60))
            let lastTaken = DoseLedger.lastTaken(medicationID: medID) ?? .distantPast
            let dueDose = med.fireDates(after: lookBack, limit: 8)
                .filter { $0 <= now && $0 > lastTaken }
                .last
                .flatMap { alarms.wasScheduled(doseKey: DoseAlarms.doseKey(medicationID: medID, doseDate: $0)) ? $0 : nil }

            let upcoming = med.nextFireDates(limit: Self.dosesAhead)
            let current = dueDose ?? upcoming.first
            guard let current else { continue }
            let later = upcoming.filter { $0 > current }.prefix(Self.dosesAhead - 1)

            doses.append(SharedState.Dose(medicationID: medID, name: med.name, doseDate: current))

            guard useAlarms else {
                await NotificationService.shared.scheduleAlarm(
                    identifier: "\(med.notificationIdentifier)_occ0",
                    medicationName: med.name,
                    fireDate: current,
                    sound: med.sound,
                    reNagCount: reNagsPerMed,
                    medicationID: medID
                )
                continue
            }

            func request(_ doseDate: Date, slot: Int, at fireDate: Date) -> DoseAlarmRequest {
                DoseAlarmRequest(
                    doseKey: DoseAlarms.doseKey(medicationID: medID, doseDate: doseDate),
                    medicationID: medID,
                    medicationName: med.name,
                    doseDate: doseDate,
                    slot: slot,
                    fireDate: fireDate,
                    sound: med.sound
                )
            }

            // The current dose: first ring plus re-alerts. After a snooze the
            // re-alerts restart from the end of the snooze.
            let currentKey = DoseAlarms.doseKey(medicationID: medID, doseDate: current)
            let reNagBase = DoseLedger.snoozedUntil(doseKey: currentKey) ?? current
            requests.append(request(current, slot: 0, at: current))
            for i in 1...reNagsPerMed {
                requests.append(request(current, slot: i, at: reNagBase.addingTimeInterval(Double(i) * intervalSeconds)))
            }
            // Later doses: just the first ring. Their re-alerts are added once
            // they become the current dose (any alarm action or app open resyncs).
            for doseDate in later {
                requests.append(request(doseDate, slot: 0, at: doseDate))
            }
        }

        if useAlarms {
            // Anything AlarmKit refused (for example over its alarm limit) still
            // gets notifications so the dose isn't missed.
            let failed = await alarms.reconcile(requests)
            for (_, group) in Dictionary(grouping: failed, by: \.doseKey) {
                guard let first = group.first else { continue }
                await NotificationService.shared.scheduleAlarm(
                    identifier: "nagrx_fallback_\(first.doseKey)",
                    medicationName: first.medicationName,
                    fireDate: first.doseDate,
                    sound: first.sound,
                    reNagCount: group.map(\.slot).max() ?? 0,
                    medicationID: first.medicationID
                )
            }
        } else {
            alarms.cancelAll()
        }

        // The widget works out what's due from this schedule on its own.
        SharedState.doses = doses
        let dueNames = doses.filter { $0.doseDate <= now }.map(\.name)
        SharedState.activeMedicationNames = dueNames
        SharedState.hasActiveAlarm = !dueNames.isEmpty

        // Sync medication list to Apple Watch
        sendMedicationsToWatch(from: container)
    }

    /// Marks every dose that's due right now as taken — the widget's "Take now"
    /// and the Watch's "I Took It" — then rebuilds the schedule.
    @MainActor
    func markAllDueTaken() async {
        let now = Date()
        for dose in SharedState.doses where dose.doseDate <= now {
            DoseLedger.markTaken(medicationID: dose.medicationID, doseDate: dose.doseDate)
        }
        DoseAlarms.shared.stopRinging()
        await sync()
    }

    /// Schedule a newly added medication.
    @MainActor
    func scheduleMedication(_ med: Medication) async {
        await sync()
    }

    /// Cancel notifications for a medication being deleted or disabled. Its alarms
    /// are removed by the sync that follows.
    func cancelMedication(_ med: Medication) {
        NotificationService.shared.cancel(identifiers: ["\(med.notificationIdentifier)_occ0"])
    }

    // MARK: - Background refresh

    /// Registers the background refresh handler. Call before launch finishes.
    func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            self.scheduleBackgroundRefresh()
            let work = Task { @MainActor in
                await self.sync()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks iOS to wake NagRX periodically to keep doses booked ahead. iOS
    /// decides the actual timing.
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
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

        let fingerprint = data + Data("|\(reNagMinutes)".utf8)
        guard fingerprint != lastWatchPayload else {
            print("[NagRX] Watch sync skipped: medication list unchanged")
            return
        }
        lastWatchPayload = fingerprint

        print("[NagRX] Sending \(watchMeds.count) medications to Watch (reNag: \(reNagMinutes)min, reachable: \(session.isReachable))")

        // Anything still queued carries an older list; the new payload supersedes it.
        session.outstandingUserInfoTransfers.forEach { $0.cancel() }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[NagRX] sendMessage failed: \(error), falling back to transferUserInfo")
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
}
