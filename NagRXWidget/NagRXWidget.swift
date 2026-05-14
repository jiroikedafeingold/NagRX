import WidgetKit
import SwiftUI

// MARK: - Shared State (for widget target access)

private enum WidgetSharedState {
    static let suiteName = "group.com.jirofeingold.NagRX"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static var hasActiveAlarm: Bool {
        defaults?.bool(forKey: "hasActiveAlarm") ?? false
    }

    static var activeMedicationNames: [String] {
        defaults?.stringArray(forKey: "activeMedicationNames") ?? []
    }
}

// MARK: - Timeline Entry

struct NagRXWidgetEntry: TimelineEntry {
    let date: Date
    let hasActiveAlarm: Bool
    let activeMedicationNames: [String]
}

// MARK: - Timeline Provider

struct NagRXWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NagRXWidgetEntry {
        NagRXWidgetEntry(date: .now, hasActiveAlarm: false, activeMedicationNames: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (NagRXWidgetEntry) -> Void) {
        let entry = NagRXWidgetEntry(
            date: .now,
            hasActiveAlarm: WidgetSharedState.hasActiveAlarm,
            activeMedicationNames: WidgetSharedState.activeMedicationNames
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NagRXWidgetEntry>) -> Void) {
        let entry = NagRXWidgetEntry(
            date: .now,
            hasActiveAlarm: WidgetSharedState.hasActiveAlarm,
            activeMedicationNames: WidgetSharedState.activeMedicationNames
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Widget Views

struct NagRXWidgetCircularView: View {
    let entry: NagRXWidgetEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.hasActiveAlarm {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .fontWeight(.bold)
                    .widgetAccentable()
            } else {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(entry.hasActiveAlarm ? URL(string: "nagrx://takenow") : nil)
    }
}

struct NagRXWidgetRectangularView: View {
    let entry: NagRXWidgetEntry

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(entry.hasActiveAlarm ? .white : .white.opacity(0.3))
                    .frame(width: 30, height: 30)
                Image(systemName: entry.hasActiveAlarm ? "pills.fill" : "pills")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(entry.hasActiveAlarm ? .black : .white)
            }

            VStack(alignment: .leading, spacing: 2) {
                if entry.hasActiveAlarm {
                    let name = entry.activeMedicationNames.first ?? "Medication"
                    Text(name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .widgetAccentable()
                    Text("TAKE NOW")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .widgetAccentable()
                } else {
                    Text("NagRX")
                        .font(.headline)
                    Text("All clear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(entry.hasActiveAlarm ? URL(string: "nagrx://takenow") : nil)
    }
}

struct NagRXWidgetSmallView: View {
    let entry: NagRXWidgetEntry

    var body: some View {
        if entry.hasActiveAlarm {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.white)

                let name = entry.activeMedicationNames.first ?? "Medication"
                Text(name.uppercased())
                    .font(.system(.headline, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("TAKE NOW")
                    .font(.system(.title3, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(Color.red, for: .widget)
            .widgetURL(URL(string: "nagrx://takenow"))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
                Text("All Clear")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct NagRXWidgetMediumView: View {
    let entry: NagRXWidgetEntry

    var body: some View {
        if entry.hasActiveAlarm {
            HStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    let names = entry.activeMedicationNames
                    if names.isEmpty {
                        Text("MEDICATION DUE")
                            .font(.system(.title2, weight: .black))
                            .foregroundStyle(.white)
                    } else {
                        Text(names.joined(separator: ", ").uppercased())
                            .font(.system(.title2, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                    }
                    Text("TAKE IT NOW!")
                        .font(.system(.title3, weight: .black))
                        .foregroundStyle(.white.opacity(0.9))
                }

                Spacer()
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(Color.red, for: .widget)
            .widgetURL(URL(string: "nagrx://takenow"))
        } else {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                    .frame(width: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NagRX")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("All Clear")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("No medications due")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 4)
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

struct NagRXWidgetLargeView: View {
    let entry: NagRXWidgetEntry

    var body: some View {
        if entry.hasActiveAlarm {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32, weight: .black))
                    Text("NagRX")
                        .font(.system(.title2, weight: .black))
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32, weight: .black))
                }
                .foregroundStyle(.white)

                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(height: 2)

                let names = entry.activeMedicationNames
                if names.isEmpty {
                    medicationRow(name: "Medication")
                } else {
                    ForEach(names.prefix(6), id: \.self) { name in
                        medicationRow(name: name)
                    }
                }

                Spacer(minLength: 0)

                Text("TAKE YOUR MEDS!")
                    .font(.system(.title, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(Color.red, for: .widget)
            .widgetURL(URL(string: "nagrx://takenow"))
        } else {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "pills")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("NagRX")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                }

                Divider()

                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("All Clear")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("No medications due right now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func medicationRow(name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pills.fill")
                .font(.title3)
                .foregroundStyle(.white)
            Text(name.uppercased())
                .font(.system(.headline, weight: .black))
                .foregroundStyle(.white)
            Spacer()
            Text("DUE NOW")
                .font(.system(.caption, weight: .black))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.25), in: Capsule())
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Widget Entry View

struct NagRXWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NagRXWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            NagRXWidgetCircularView(entry: entry)
        case .accessoryRectangular:
            NagRXWidgetRectangularView(entry: entry)
        case .systemMedium:
            NagRXWidgetMediumView(entry: entry)
        case .systemLarge:
            NagRXWidgetLargeView(entry: entry)
        default:
            NagRXWidgetSmallView(entry: entry)
        }
    }
}

// MARK: - Widget Configuration

struct NagRXWidget: Widget {
    let kind = "NagRXWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NagRXWidgetProvider()) { entry in
            NagRXWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NagRX")
        .description("Shows medication alert status.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium, .systemLarge])
        #endif
    }
}
