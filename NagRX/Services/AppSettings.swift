import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Re-nag interval in minutes (1–10, default 5).
    var reNagIntervalMinutes: Int {
        get { UserDefaults.standard.object(forKey: "reNagIntervalMinutes") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "reNagIntervalMinutes") }
    }

    /// Default alert sound for new medications.
    var defaultSound: NagRXSound {
        get {
            let raw = UserDefaults.standard.string(forKey: "defaultSound") ?? NagRXSound.pebble.rawValue
            return NagRXSound(rawValue: raw) ?? .pebble
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultSound") }
    }

    private init() {}
}
