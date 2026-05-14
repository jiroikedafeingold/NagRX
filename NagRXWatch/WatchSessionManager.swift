import Foundation
import WatchConnectivity
import UserNotifications
import WatchKit

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[NagRXWatch] WCSession activation failed: \(error)")
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["medications"] as? Data,
              let medications = try? JSONDecoder().decode([WatchMedication].self, from: data) else {
            print("[NagRXWatch] Failed to decode medications from userInfo")
            return
        }

        DispatchQueue.main.async {
            WatchDataStore.shared.update(medications: medications)
            self.scheduleNotifications(for: medications)
        }
    }

    // MARK: - Watch Notifications

    private func scheduleNotifications(for medications: [WatchMedication]) {
        let center = UNUserNotificationCenter.current()

        // Request notification permission
        center.requestAuthorization(options: [.alert, .sound, .providesAppNotificationSettings]) { granted, error in
            guard granted else {
                print("[NagRXWatch] Notification permission denied")
                return
            }

            // Cancel all existing notifications before rescheduling
            center.removeAllPendingNotificationRequests()

            let enabledMeds = medications.filter { $0.isEnabled }
            for med in enabledMeds {
                let fireDate = med.nextFireDate
                guard fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Time for \(med.name)"
                content.body = med.formattedSchedule
                content.sound = .default
                content.categoryIdentifier = "MEDICATION_ALERT"

                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "watch_\(med.id.uuidString)",
                    content: content,
                    trigger: trigger
                )

                center.add(request) { error in
                    if let error {
                        print("[NagRXWatch] Failed to schedule notification: \(error)")
                    }
                }
            }
        }
    }
}

// MARK: - Watch Notification Delegate

final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Play strong haptic when notification fires
        WKInterfaceDevice.current().play(.notification)

        // Play a second haptic burst after a short delay for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WKInterfaceDevice.current().play(.notification)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            WKInterfaceDevice.current().play(.notification)
        }

        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Tapping the notification just opens the app — no special action needed
    }
}
