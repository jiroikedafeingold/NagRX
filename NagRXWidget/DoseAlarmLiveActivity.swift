#if os(iOS)
import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - Metadata

/// IMPORTANT: identical copy of the type in NagRX/Services/DoseAlarms.swift.
/// ActivityKit matches the two by type name and Codable shape — keep them in sync.
struct DoseAlarmMetadata: AlarmMetadata {
    var medicationName: String
    var doseDate: Date
}

// MARK: - Live Activity

/// The Live Activity for a dose alarm: shown in the Dynamic Island and on the
/// Lock Screen while it's snoozed, counting down to the next ring.
struct DoseAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<DoseAlarmMetadata>.self) { context in
            DoseLockScreenView(metadata: context.attributes.metadata, state: context.state)
                .activityBackgroundTint(Color.red.opacity(0.25))
                .activitySystemActionForegroundColor(.red)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Snoozed", systemImage: "zzz")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RingCountdown(state: context.state)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DoseSummary(metadata: context.attributes.metadata)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.red)
            } compactTrailing: {
                RingCountdown(state: context.state)
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

/// Time until the snoozed alarm rings again.
private struct RingCountdown: View {
    let state: AlarmPresentationState

    var body: some View {
        switch state.mode {
        case .countdown(let countdown) where countdown.fireDate > .now:
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        case .paused:
            Text("Paused")
        default:
            Image(systemName: "alarm.waves.left.and.right")
        }
    }
}

private struct DoseSummary: View {
    let metadata: DoseAlarmMetadata?

    var body: some View {
        if let metadata {
            VStack(alignment: .leading, spacing: 3) {
                Text("Take \(metadata.medicationName)")
                    .font(.headline)
                    .lineLimit(1)
                // Counts up: how long the dose has been waiting.
                Text("Due \(metadata.doseDate, style: .time) · \(metadata.doseDate, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct DoseLockScreenView: View {
    let metadata: DoseAlarmMetadata?
    let state: AlarmPresentationState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Snoozed", systemImage: "zzz")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Spacer()
                RingCountdown(state: state)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            DoseSummary(metadata: metadata)
        }
        .padding(16)
    }
}
#endif
