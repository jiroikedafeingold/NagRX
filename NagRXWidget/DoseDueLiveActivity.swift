#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Attributes

/// IMPORTANT: identical copy of the type in NagRX/Services/DoseLiveActivities.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct DoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {}

    var medicationID: String
    var medicationName: String
    var doseDate: Date
}

// MARK: - Intent

/// Copy of the app's intent so the widget can build the Taken button. As a
/// LiveActivityIntent the system runs the app's version, in the app's process.
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
        .result()
    }
}

// MARK: - Live Activity

/// "Take X" on the Lock Screen and in the Dynamic Island from the dose time
/// until the person taps Taken.
struct DoseDueLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DoseActivityAttributes.self) { context in
            DoseDueLockScreenView(attributes: context.attributes)
                .activityBackgroundTint(Color.red.opacity(0.25))
                .activitySystemActionForegroundColor(.red)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Due", systemImage: "pills.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WaitingTime(doseDate: context.attributes.doseDate)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        DoseDueSummary(attributes: context.attributes)
                        Spacer()
                        TakenButton(attributes: context.attributes)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                WaitingTime(doseDate: context.attributes.doseDate)
                    .frame(maxWidth: 64)
                    .foregroundStyle(.red)
            } minimal: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.red)
            }
            .keylineTint(.red)
        }
    }
}

// MARK: - Views

/// Counts up: how long the dose has been waiting.
private struct WaitingTime: View {
    let doseDate: Date

    var body: some View {
        Text(doseDate, style: .timer)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

private struct DoseDueSummary: View {
    let attributes: DoseActivityAttributes

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Take \(attributes.medicationName)")
                .font(.headline)
                .lineLimit(1)
            Text("Due \(attributes.doseDate, style: .time)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct TakenButton: View {
    let attributes: DoseActivityAttributes

    var body: some View {
        Button(intent: DoseActivityTakenIntent(
            medicationID: attributes.medicationID,
            doseTimestamp: Int(attributes.doseDate.timeIntervalSince1970)
        )) {
            Label("Taken", systemImage: "checkmark")
                .font(.subheadline.weight(.semibold))
        }
        .tint(.red)
    }
}

private struct DoseDueLockScreenView: View {
    let attributes: DoseActivityAttributes

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.title2)
                .foregroundStyle(.red)
            DoseDueSummary(attributes: attributes)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                WaitingTime(doseDate: attributes.doseDate)
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 90, alignment: .trailing)
                TakenButton(attributes: attributes)
            }
        }
        .padding(16)
    }
}
#endif
