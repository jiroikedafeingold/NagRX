import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize notification service (sets itself as delegate)
        _ = NotificationService.shared

        // Register the background refresh handler before launch finishes.
        NagScheduler.shared.registerBackgroundRefresh()

        // Ask for notifications (fallback + silent reminders). Alarms are asked
        // for once the app is on screen, in applicationDidBecomeActive.
        Task { @MainActor in
            await NotificationService.shared.requestPermission()
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Clear badge
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }

        // Ask for alarms the first time (how doses ring through silent mode),
        // then sync.
        Task { @MainActor in
            if DoseAlarms.shared.isUndetermined {
                await DoseAlarms.shared.requestAuthorization()
            }
            await NagScheduler.shared.sync()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        NagScheduler.shared.scheduleBackgroundRefresh()
    }
}
