import SwiftUI
import UserNotifications

@main
struct NagRXWatch_Watch_AppApp: App {
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
