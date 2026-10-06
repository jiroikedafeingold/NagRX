import Foundation
import WidgetKit

enum SharedState {
    static let suiteName = "group.com.jirofeingold.NagRX"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // Both setters are written on every sync(), and sync() runs on every
    // foreground. Each reload spawns the widget extension process, so skip the
    // write and the reload entirely when the value hasn't actually moved.

    static var hasActiveAlarm: Bool {
        get { defaults?.bool(forKey: "hasActiveAlarm") ?? false }
        set {
            guard newValue != hasActiveAlarm else { return }
            defaults?.set(newValue, forKey: "hasActiveAlarm")
            defaults?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var activeMedicationNames: [String] {
        get { defaults?.stringArray(forKey: "activeMedicationNames") ?? [] }
        set {
            guard newValue != activeMedicationNames else { return }
            defaults?.set(newValue, forKey: "activeMedicationNames")
            defaults?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// The dose each medication is currently on (due, or next up). The widget
    /// reads this to switch to "Take now" at the dose time by itself, since the
    /// app no longer runs in the background to tell it.
    struct Dose: Codable, Equatable {
        var medicationID: String
        var name: String
        var doseDate: Date
    }

    static var doses: [Dose] {
        get {
            guard let data = defaults?.data(forKey: "doses"),
                  let doses = try? JSONDecoder().decode([Dose].self, from: data) else { return [] }
            return doses
        }
        set {
            guard newValue != doses, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults?.set(data, forKey: "doses")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
