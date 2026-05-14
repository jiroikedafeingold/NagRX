import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize notification service (sets itself as delegate)
        _ = NotificationService.shared

        // Start silent audio loop to keep the app alive in background
        BackgroundAudioKeepAlive.shared.start()

        // Request notification permission
        Task {
            await NotificationService.shared.requestPermission()
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Re-ensure background audio is running
        BackgroundAudioKeepAlive.shared.start()

        // Clear badge
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }

        // Sync alarms
        Task { @MainActor in
            await NagScheduler.shared.sync()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Ensure background audio keep-alive is running
        BackgroundAudioKeepAlive.shared.start()
    }
}
