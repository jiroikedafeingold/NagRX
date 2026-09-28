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
}
