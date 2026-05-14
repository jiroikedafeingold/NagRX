import Foundation
import WatchConnectivity
import UserNotifications
import WatchKit

// MARK: - Watch Alarm Actions

enum WatchAlarmAction {
    static let snooze    = "WATCH_SNOOZE"
    static let snooze90  = "WATCH_SNOOZE_90"
    static let snoozeDay = "WATCH_SNOOZE_DAY"
    static let dismiss   = "WATCH_DISMISS"
    static let category  = "MEDICATION_ALERT"
}

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        registerCategories()
    }

    private func registerCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: WatchAlarmAction.snooze,
            title: "Snooze 15 min",
            options: []
        )
        let snooze90Action = UNNotificationAction(
            identifier: WatchAlarmAction.snooze90,
            title: "Snooze 90 min",
            options: []
        )
        let snoozeDayAction = UNNotificationAction(
            identifier: WatchAlarmAction.snoozeDay,
            title: "Snooze 1 day",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: WatchAlarmAction.dismiss,
            title: "I Took It",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: WatchAlarmAction.category,
            actions: [snoozeAction, snooze90Action, snoozeDayAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[NagRXWatch] WCSession activation failed: \(error)")
        } else {
            print("[NagRXWatch] WCSession activated (state: \(activationState.rawValue))")
            requestSyncFromPhone()
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handlePayload(userInfo, source: "userInfo")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["action"] as? String == "dismiss" {
            print("[NagRXWatch] Phone dismissed alarm — cancelling Watch alerts")
            DispatchQueue.main.async {
                UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                WatchNotificationDelegate.shared.stopHapticBurst()
            }
            return
        }
        handlePayload(message, source: "message")
    }

    private func handlePayload(_ payload: [String: Any], source: String) {
        guard let data = payload["medications"] as? Data,
              let medications = try? JSONDecoder().decode([WatchMedication].self, from: data) else {
            print("[NagRXWatch] Failed to decode medications from \(source)")
            return
        }

        let reNagMinutes = payload["reNagIntervalMinutes"] as? Int ?? 5

        print("[NagRXWatch] Received \(medications.count) medications via \(source) (reNag: \(reNagMinutes)min)")
        DispatchQueue.main.async {
            WatchDataStore.shared.update(medications: medications)
            WatchDataStore.shared.reNagIntervalMinutes = reNagMinutes
            self.scheduleNotifications(for: medications, reNagMinutes: reNagMinutes)
        }
    }

    func requestSyncFromPhone() {
        guard WCSession.default.isReachable else {
            print("[NagRXWatch] Phone not reachable, can't request sync")
            return
        }
        WCSession.default.sendMessage(["request": "sync"], replyHandler: nil) { error in
            print("[NagRXWatch] Failed to request sync: \(error)")
        }
    }

    /// Tell the phone to dismiss all alerts (called when user acts on Watch).
    func sendDismissToPhone() {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["action": "dismiss"]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { error in
                print("[NagRXWatch] Failed to send dismiss to phone: \(error)")
            }
        }
    }

    // MARK: - Watch Notifications

    private func scheduleNotifications(for medications: [WatchMedication], reNagMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        let reNagInterval = TimeInterval(reNagMinutes * 60)
        let reNagCount = 5

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                print("[NagRXWatch] Notification permission denied")
                return
            }

            center.removeAllPendingNotificationRequests()

            let enabledMeds = medications.filter { $0.isEnabled }
            for med in enabledMeds {
                let baseDate = med.nextFireDate
                guard baseDate > Date() else { continue }

                for nagIndex in 0...reNagCount {
                    let fireDate = baseDate.addingTimeInterval(Double(nagIndex) * reNagInterval)
                    guard fireDate > Date() else { continue }

                    let content = UNMutableNotificationContent()
                    if nagIndex == 0 {
                        content.title = "Time for \(med.name)"
                        content.body = med.formattedSchedule
                    } else {
                        content.title = "Take \(med.name) NOW"
                        content.body = "Reminder #\(nagIndex) — don't forget!"
                    }
                    content.sound = .default
                    content.interruptionLevel = .timeSensitive
                    content.categoryIdentifier = WatchAlarmAction.category
                    content.userInfo["medicationName"] = med.name

                    let comps = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second],
                        from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: "watch_\(med.id.uuidString)_r\(nagIndex)",
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
}

// MARK: - Watch Notification Delegate

final class WatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationDelegate()
    private var runtimeSession: WKExtendedRuntimeSession?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        startHapticBurst()
        scheduleNextWatchReNag(from: notification.request)
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content

        switch response.actionIdentifier {
        case WatchAlarmAction.snooze, UNNotificationDefaultActionIdentifier:
            stopHapticBurst()
            cancelAllWatch()
            scheduleWatchSnooze(content: content, minutes: 15)

        case WatchAlarmAction.snooze90:
            stopHapticBurst()
            cancelAllWatch()
            scheduleWatchSnooze(content: content, minutes: 90)

        case WatchAlarmAction.snoozeDay:
            stopHapticBurst()
            cancelAllWatch()
            scheduleWatchSnooze(content: content, minutes: 24 * 60)

        case WatchAlarmAction.dismiss, UNNotificationDismissActionIdentifier:
            stopHapticBurst()
            cancelAllWatch()
            WatchSessionManager.shared.sendDismissToPhone()

        default:
            stopHapticBurst()
            cancelAllWatch()
        }
    }

    private func cancelAllWatch() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func scheduleWatchSnooze(content: UNNotificationContent, minutes: Int) {
        let snoozeSeconds = TimeInterval(minutes * 60)
        let mutable = content.mutableCopy() as! UNMutableNotificationContent
        mutable.subtitle = "Snoozed — take your medication"
        mutable.categoryIdentifier = WatchAlarmAction.category

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: snoozeSeconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "watch_snooze",
            content: mutable,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[NagRXWatch] Snooze schedule failed: \(error)") }
        }
    }

    private func scheduleNextWatchReNag(from request: UNNotificationRequest) {
        let interval = TimeInterval(WatchDataStore.shared.reNagIntervalMinutes * 60)
        let currentID = request.identifier

        let nextNumber: Int
        if let range = currentID.range(of: "_r(\\d+)$", options: .regularExpression) {
            let numStr = currentID[range].dropFirst(2)
            nextNumber = (Int(numStr) ?? 0) + 1
        } else {
            nextNumber = 1
        }

        let baseID: String
        if let range = currentID.range(of: "_r\\d+$", options: .regularExpression) {
            baseID = String(currentID[currentID.startIndex..<range.lowerBound])
        } else {
            baseID = currentID
        }

        let nextID = "\(baseID)_r\(nextNumber)"

        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = "STILL WAITING — take your medication!"
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = WatchAlarmAction.category
        content.userInfo = request.content.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let nextRequest = UNNotificationRequest(identifier: nextID, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(nextRequest) { error in
            if let error {
                print("[NagRXWatch] Failed to schedule next re-nag: \(error)")
            }
        }
    }

    func startHapticBurst() {
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        session.start()
        runtimeSession = session

        Task { @MainActor in
            let device = WKInterfaceDevice.current()
            for i in 0..<10 {
                device.play(.notification)
                if i < 9 {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            self.runtimeSession?.invalidate()
            self.runtimeSession = nil
        }
    }

    func stopHapticBurst() {
        runtimeSession?.invalidate()
        runtimeSession = nil
    }
}

extension WatchNotificationDelegate: WKExtendedRuntimeSessionDelegate {
    func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: (any Error)?) {}
    func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
    func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}
}
