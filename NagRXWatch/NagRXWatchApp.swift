import SwiftUI
import UserNotifications

@main
struct NagRXWatchApp: App {
    init() {
        WatchSessionManager.shared.activate()
        UNUserNotificationCenter.current().delegate = WatchNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            MedicationListWatch()
        }
    }
}
