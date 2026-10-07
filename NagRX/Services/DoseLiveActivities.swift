import Foundation
import ActivityKit
import AppIntents

// MARK: - Attributes

/// A "Take X" Live Activity that stays on the Lock Screen and in the Dynamic
/// Island from the dose time until the person taps Taken.
///
/// IMPORTANT: an identical copy lives in NagRXWidget/DoseDueLiveActivity.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
nonisolated struct DoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    var medicationID: String
    var medicationName: String
    var doseDate: Date
}

// MARK: - DoseLiveActivities

/// Keeps one dose Live Activity per medication's current dose.
///
/// NagRX is usually suspended when a dose comes due, and a suspended app can't
/// start a Live Activity. So each sync schedules the activity for the dose time
/// and the system starts it then; a dose that's already due gets one right away.
@MainActor
enum DoseLiveActivities {
    /// Dose key → dose date for every activity ever started, so a dose whose
    /// activity the person swiped away isn't brought back on the next sync.
    private static let startedKey = "DoseLiveActivitiesStarted"

    /// Whether NagRX ever started (or scheduled) this dose's activity.
    static func wasStarted(doseKey: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: startedKey) as? [String: Double])?[doseKey] != nil
    }

    static func sync(doses: [SharedState.Dose]) async {
        let wanted = Dictionary(
            doses.map { (DoseAlarms.doseKey(medicationID: $0.medicationID, doseDate: $0.doseDate), $0) },
            uniquingKeysWith: { a, _ in a }
        )

        // End activities for doses that were taken or rescheduled.
        var running: Set<String> = []
        for activity in Activity<DoseActivityAttributes>.activities {
            let key = DoseAlarms.doseKey(medicationID: activity.attributes.medicationID,
                                         doseDate: activity.attributes.doseDate)
            let live = activity.activityState == .active || activity.activityState == .pending
                || activity.activityState == .stale
            if live, wanted[key] != nil, !running.contains(key) {
                running.insert(key)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        var started = UserDefaults.standard.dictionary(forKey: startedKey) as? [String: Double] ?? [:]
        for (key, dose) in wanted where !running.contains(key) && started[key] == nil {
            let attributes = DoseActivityAttributes(medicationID: dose.medicationID,
                                                    medicationName: dose.name,
                                                    doseDate: dose.doseDate)
            let content = ActivityContent(state: DoseActivityAttributes.ContentState(), staleDate: nil)
            do {
                if dose.doseDate <= now {
                    // Already due: start now. Only works while NagRX is in the
                    // foreground or running an alarm/Live Activity intent.
                    _ = try Activity.request(attributes: attributes, content: content)
                } else {
                    // The system starts it at the dose time even if NagRX is suspended.
                    _ = try Activity.request(
                        attributes: attributes,
                        content: content,
                        style: .standard,
                        alertConfiguration: AlertConfiguration(
                            title: "Take \(dose.name)",
                            body: "It's time for your dose.",
                            sound: .default
                        ),
                        start: dose.doseDate
                    )
                }
                started[key] = dose.doseDate.timeIntervalSince1970
            } catch {
                print("[NagRX] Dose Live Activity failed: \(error)")
            }
        }

        let cutoff = now.addingTimeInterval(-2 * 86_400).timeIntervalSince1970
        UserDefaults.standard.set(started.filter { $0.value > cutoff }, forKey: startedKey)
    }
}

// MARK: - Intent

/// The Taken button on the dose Live Activity. Runs in NagRX's process.
///
/// IMPORTANT: a matching copy (with an empty perform) lives in
/// NagRXWidget/DoseDueLiveActivity.swift so the widget can build the button.
struct DoseActivityTakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Dose Taken"
    static let isDiscoverable = false

    @Parameter(title: "Medication")
    var medicationID: String

    @Parameter(title: "Dose Time")
    var doseTimestamp: Int

    init() {}

    init(medicationID: String, doseTimestamp: Int) {
        self.medicationID = medicationID
        self.doseTimestamp = doseTimestamp
    }

    func perform() async throws -> some IntentResult {
        let medicationID = medicationID
        let doseDate = Date(timeIntervalSince1970: TimeInterval(doseTimestamp))
        await MainActor.run { DoseAlarms.shared.stopRinging() }
        // Records the dose, tells the Watch, and resyncs — which ends this activity.
        await DoseAlarms.shared.handleAction(medicationID: medicationID, doseDate: doseDate, taken: true)
        return .result()
    }
}
