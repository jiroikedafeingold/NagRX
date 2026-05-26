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

    /// Show the on-screen celebration animation + success haptics when a medication is marked taken.
    /// Off by default — when off, the "I Took It" notification action stays in the background and
    /// doesn't open the app.
    var celebrationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "celebrationEnabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "celebrationEnabled") }
    }

    private init() {}
}
