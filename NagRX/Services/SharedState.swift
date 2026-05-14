import Foundation
import WidgetKit

enum SharedState {
    static let suiteName = "group.com.jirofeingold.NagRX"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static var hasActiveAlarm: Bool {
        get { defaults?.bool(forKey: "hasActiveAlarm") ?? false }
        set {
            defaults?.set(newValue, forKey: "hasActiveAlarm")
            defaults?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var activeMedicationNames: [String] {
        get { defaults?.stringArray(forKey: "activeMedicationNames") ?? [] }
        set {
            defaults?.set(newValue, forKey: "activeMedicationNames")
            defaults?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
