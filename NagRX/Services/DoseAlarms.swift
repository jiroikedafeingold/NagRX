import Foundation
import CryptoKit
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

// MARK: - Request

/// One alarm NagRX wants to exist: a dose's first ring (slot 0) or one of its
/// re-alerts (slot 1, 2, …).
struct DoseAlarmRequest: Sendable {
    /// Identifies the dose: medication + scheduled time.
    let doseKey: String
    let medicationID: String
    let medicationName: String
    /// When the dose is scheduled.
    let doseDate: Date
    let slot: Int
    /// The intended ring time. May already be in the past; see DoseAlarms.reconcile.
    let fireDate: Date
    let sound: NagRXSound

    var id: UUID { DoseAlarms.alarmID(doseKey: doseKey, slot: slot) }

    /// Everything baked into a scheduled alarm. If it changes, the alarm is rescheduled.
    var fingerprint: String {
        "\(slot)|\(Int(fireDate.timeIntervalSince1970))|\(medicationName)|\(sound.rawValue)"
    }
}

// MARK: - Ledger

/// What the person has done with each dose, kept so a resync never re-nags a
/// dose they already took.
enum DoseLedger {
    private static let takenKey = "DoseLedgerTaken"       // medication ID → last taken dose date
    private static let snoozeKey = "DoseLedgerSnoozed"    // dose key → snoozed-until date

    /// The most recent dose date the person confirmed for each medication.
    static func lastTaken(medicationID: String) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: takenKey) as? [String: Double] ?? [:]
        return all[medicationID].map(Date.init(timeIntervalSince1970:))
    }

    static func markTaken(medicationID: String, doseDate: Date) {
        var all = UserDefaults.standard.dictionary(forKey: takenKey) as? [String: Double] ?? [:]
        all[medicationID] = max(all[medicationID] ?? 0, doseDate.timeIntervalSince1970)
        UserDefaults.standard.set(all, forKey: takenKey)
    }

    static func snoozedUntil(doseKey: String) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Double] ?? [:]
        return all[doseKey].map(Date.init(timeIntervalSince1970:))
    }

    static func markSnoozed(doseKey: String, until date: Date) {
        var all = UserDefaults.standard.dictionary(forKey: snoozeKey) as? [String: Double] ?? [:]
        all[doseKey] = date.timeIntervalSince1970
        // Forget snoozes more than a day old.
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        UserDefaults.standard.set(all.filter { $0.value > cutoff }, forKey: snoozeKey)
    }
}

// MARK: - DoseAlarms

/// Schedules NagRX's medication alarms with AlarmKit.
///
/// AlarmKit alarms are real system alarms: they ring through silent mode and
/// Focus, and the system rings them even when NagRX isn't running. That's what
/// lets NagRX stay suspended in the background instead of keeping itself alive.
@MainActor
final class DoseAlarms {
    static let shared = DoseAlarms()

    /// Snooze length on the alarm's Snooze button.
    static let snoozeMinutes = 15

    private let manager = AlarmManager.shared

    private init() {}

    /// Stable alarm ID per dose and slot, so every sync addresses the same alarm.
    nonisolated static func alarmID(doseKey: String, slot: Int) -> UUID {
        var bytes = Array(Insecure.MD5.hash(data: Data("\(doseKey)|\(slot)".utf8)))
        bytes[6] = (bytes[6] & 0x0F) | 0x30   // name-based UUID (version 3)
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }

    nonisolated static func doseKey(medicationID: String, doseDate: Date) -> String {
        "\(medicationID)_\(Int(doseDate.timeIntervalSince1970))"
    }

    /// NagRX's alarms as the system has them. Empty if they can't be read.
    private var currentAlarms: [Alarm] { (try? manager.alarms) ?? [] }

    var isAuthorized: Bool { manager.authorizationState == .authorized }
    var isDenied: Bool { manager.authorizationState == .denied }
    var isUndetermined: Bool { manager.authorizationState == .notDetermined }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await manager.requestAuthorization()) == .authorized
    }

    /// Whether NagRX ever scheduled this dose's first alarm. A dose that's already
    /// due is only nagged about if NagRX actually alarmed for it — so updating
    /// the app never starts nagging about a dose that was taken under the old
    /// notification-based version.
    func wasScheduled(doseKey: String) -> Bool {
        history[Self.alarmID(doseKey: doseKey, slot: 0).uuidString] != nil
    }

    // MARK: Bookkeeping

    private static let fingerprintsKey = "DoseAlarmFingerprints"
    /// Alarm ID → intended fire date for every alarm ever scheduled. Stops an
    /// alarm whose time has passed from being rescheduled after it rang.
    private static let historyKey = "DoseAlarmHistory"

    private var fingerprints: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.fingerprintsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.fingerprintsKey) }
    }
    private var history: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.historyKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.historyKey) }
    }

    /// The test alarm from Settings, which a resync must not cancel.
    private var protectedIDs: Set<UUID> = []

    // MARK: Scheduling

    /// Makes the scheduled alarms match `requests`.
    ///
    /// Alarms that are ringing or snoozed are never touched, so a resync can't cut
    /// off an alarm in progress. Returns the requests that couldn't be scheduled
    /// (for example over the system's alarm limit) so the caller can fall back to
    /// notifications.
    func reconcile(_ requests: [DoseAlarmRequest]) async -> [DoseAlarmRequest] {
        let now = Date()
        var fingerprints = self.fingerprints
        var history = self.history

        let existing = Dictionary(currentAlarms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let wantedByID = Dictionary(requests.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for (id, alarm) in existing where alarm.state == .scheduled && !protectedIDs.contains(id) {
            let key = id.uuidString
            if let request = wantedByID[id], fingerprints[key] == request.fingerprint { continue }
            try? manager.cancel(id: id)
            fingerprints[key] = nil
        }

        var failed: [DoseAlarmRequest] = []
        for request in requests {
            let key = request.id.uuidString
            if let alarm = existing[request.id] {
                if alarm.state != .scheduled { continue }               // ringing or snoozed
                if fingerprints[key] == request.fingerprint { continue } // unchanged
            }

            var ringAt = request.fireDate
            if ringAt <= now.addingTimeInterval(5) {
                // The ring time has passed. Ring now only if this alarm never rang.
                guard history[key] == nil else { continue }
                ringAt = now.addingTimeInterval(5)
            }

            do {
                _ = try await manager.schedule(id: request.id, configuration: configuration(for: request, at: ringAt))
                fingerprints[key] = request.fingerprint
                history[key] = request.fireDate.timeIntervalSince1970
            } catch {
                print("[NagRX] Scheduling alarm failed: \(error)")
                failed.append(request)
            }
        }

        let cutoff = now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970
        let liveIDs = Set(currentAlarms.map(\.id.uuidString))
        self.history = history.filter { $0.value > cutoff }
        self.fingerprints = fingerprints.filter { liveIDs.contains($0.key) }
        return failed
    }

    /// Cancels every scheduled NagRX alarm. Alarms ringing or snoozed are left alone.
    func cancelAll() {
        for alarm in currentAlarms where alarm.state == .scheduled {
            try? manager.cancel(id: alarm.id)
        }
        fingerprints = [:]
    }

    /// Stops any ringing alarms and cancels all scheduled re-alerts for doses
    /// that are due — used when the person confirms from the widget or Watch.
    func stopRinging() {
        for alarm in currentAlarms where alarm.state == .alerting || alarm.state == .countdown {
            try? manager.stop(id: alarm.id)
        }
    }

    /// A one-off alarm in a few seconds, from Settings → Test.
    func scheduleTest(sound: NagRXSound) async -> Bool {
        let request = DoseAlarmRequest(
            doseKey: "test_\(UUID().uuidString)",
            medicationID: "test",
            medicationName: "Test Medication",
            doseDate: Date().addingTimeInterval(5),
            slot: 0,
            fireDate: Date().addingTimeInterval(5),
            sound: sound
        )
        protectedIDs.insert(request.id)
        do {
            _ = try await manager.schedule(id: request.id, configuration: configuration(for: request, at: request.fireDate))
            return true
        } catch {
            print("[NagRX] Test alarm failed: \(error)")
            return false
        }
    }

    private func configuration(
        for request: DoseAlarmRequest,
        at ringAt: Date
    ) -> AlarmManager.AlarmConfiguration<DoseAlarmMetadata> {
        let title = request.slot == 0
            ? "Take \(request.medicationName)"
            : "STILL WAITING: take \(request.medicationName)"
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: request.medicationName))
            ),
            metadata: DoseAlarmMetadata(medicationName: request.medicationName, doseDate: request.doseDate),
            tintColor: .red
        )
        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: Double(Self.snoozeMinutes) * 60),
            schedule: .fixed(ringAt),
            attributes: attributes,
            stopIntent: DoseAlarmIntent(medicationID: request.medicationID,
                                        doseTimestamp: Int(request.doseDate.timeIntervalSince1970),
                                        action: "taken"),
            secondaryIntent: DoseAlarmIntent(medicationID: request.medicationID,
                                             doseTimestamp: Int(request.doseDate.timeIntervalSince1970),
                                             action: "snooze"),
            sound: .named(request.sound.alertFileName)
        )
    }

    // MARK: Alarm actions

    /// Called when the person taps Stop ("I took it") or Snooze on a dose alarm.
    func handleAction(medicationID: String, doseDate: Date, taken: Bool) async {
        guard medicationID != "test" else { return }
        if taken {
            DoseLedger.markTaken(medicationID: medicationID, doseDate: doseDate)
            NotificationService.shared.sendDismissToWatch()
            CelebrationManager.shared.celebrate()
        } else {
            // Re-alerts resume at the usual interval after the snooze ends.
            DoseLedger.markSnoozed(
                doseKey: Self.doseKey(medicationID: medicationID, doseDate: doseDate),
                until: Date().addingTimeInterval(Double(Self.snoozeMinutes) * 60)
            )
        }
        // NagRX is awake anyway: rebuild the schedule, which also clears the
        // taken dose's remaining re-alerts and shifts a snoozed dose's ones.
        // Awaited so the system doesn't suspend the app mid-sync.
        await NagScheduler.shared.sync()
    }
}

// MARK: - Metadata

/// Dose details shown in the alarm's Live Activity while it's snoozed.
///
/// IMPORTANT: an identical copy lives in NagRXWidget/DoseAlarmLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct DoseAlarmMetadata: AlarmMetadata {
    var medicationName: String
    var doseDate: Date
}

// MARK: - Intent

/// Runs in NagRX when the person taps Stop or Snooze on a dose alarm.
struct DoseAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Medication Alarm Action"
    static let isDiscoverable = false

    @Parameter(title: "Medication")
    var medicationID: String

    @Parameter(title: "Dose Time")
    var doseTimestamp: Int

    @Parameter(title: "Action")
    var action: String

    init() {}

    init(medicationID: String, doseTimestamp: Int, action: String) {
        self.medicationID = medicationID
        self.doseTimestamp = doseTimestamp
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        let medicationID = medicationID
        let doseDate = Date(timeIntervalSince1970: TimeInterval(doseTimestamp))
        let taken = action == "taken"
        await DoseAlarms.shared.handleAction(medicationID: medicationID, doseDate: doseDate, taken: taken)
        return .result()
    }
}
