import UserNotifications
import Foundation
import CoreHaptics
import UIKit
import WatchConnectivity

// MARK: - Action / Category identifiers

enum AlarmAction {
    static let snooze       = "NAGRX_SNOOZE"
    static let snooze90     = "NAGRX_SNOOZE_90"
    static let snoozeDay    = "NAGRX_SNOOZE_DAY"
    static let dismiss      = "NAGRX_DISMISS"
    static let category     = "NAGRX_ALARM"
}

// MARK: - NotificationService

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var hapticStopWork: DispatchWorkItem?
    private var hapticFallbackItems: [DispatchWorkItem] = []
    private var hapticRepeatTimer: Timer?

    private override init() {
        super.init()
        center.delegate = self
        registerCategories()
        prepareHapticEngine()
    }

    // MARK: Authorization

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    func checkPermission() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: Category Registration

    func registerCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: AlarmAction.snooze,
            title: "Snooze 15 min",
            options: []
        )
        let snooze90Action = UNNotificationAction(
            identifier: AlarmAction.snooze90,
            title: "Snooze 90 min",
            options: []
        )
        let snoozeDayAction = UNNotificationAction(
            identifier: AlarmAction.snoozeDay,
            title: "Snooze 1 day",
            options: []
        )
        // Only request foreground launch on dismiss when celebrations are on. Foregrounding is
        // required for CoreHaptics + the on-screen overlay to actually run; if the user has
        // celebrations off, we want the action to stay in the background instead.
        var dismissOptions: UNNotificationActionOptions = [.destructive]
        if AppSettings.shared.celebrationEnabled {
            dismissOptions.insert(.foreground)
        }
        let dismissAction = UNNotificationAction(
            identifier: AlarmAction.dismiss,
            title: "I Took It",
            options: dismissOptions
        )
        let alarmCategory = UNNotificationCategory(
            identifier: AlarmAction.category,
            actions: [snoozeAction, snooze90Action, snoozeDayAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([alarmCategory])
    }

    // MARK: Schedule

    /// Schedules a medication alarm with re-nag follow-ups at the configured interval.
    /// Returns the primary notification identifier.
    @discardableResult
    func scheduleAlarm(
        identifier: String,
        medicationName: String,
        fireDate: Date,
        sound: NagRXSound,
        reNagCount: Int = 60,
        silentReminder: Bool = false
    ) async -> String {
        if silentReminder {
            await schedule(
                id: identifier,
                title: "Take \(medicationName)",
                subtitle: "Time to take your medication",
                threadID: identifier,
                date: fireDate,
                sound: sound,
                isSilent: true
            )
            return identifier
        }

        let intervalSeconds = Double(AppSettings.shared.reNagIntervalMinutes) * 60

        let rings: [(id: String, date: Date, subtitle: String)] = (0...reNagCount).compactMap { i in
            let date = fireDate.addingTimeInterval(Double(i) * intervalSeconds)
            guard date > Date() else { return nil }
            let subtitle: String
            switch i {
            case 0: subtitle = "Time to take your medication"
            case 1, 2: subtitle = "Reminder: take \(medicationName)"
            default: subtitle = "STILL WAITING: \(medicationName)"
            }
            let suffix = i == 0 ? "" : "_r\(i)"
            return (id: identifier + suffix, date: date, subtitle: subtitle)
        }

        for ring in rings {
            await schedule(
                id: ring.id,
                title: "Take \(medicationName)",
                subtitle: ring.subtitle,
                threadID: identifier,
                date: ring.date,
                sound: sound,
                isSilent: false
            )
        }

        return identifier
    }

    // MARK: Cancel

    func cancel(identifiers: [String]) {
        // Cancel all pending and delivered notifications — with unlimited re-nags
        // we can't enumerate all IDs, so just remove everything and let sync reschedule.
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Remove all previously delivered notifications so only the latest remains
        center.removeAllDeliveredNotifications()

        let isSilent = notification.request.content.userInfo["silentReminder"] as? Bool ?? false

        if isSilent {
            startRepeatingHaptics()
            completionHandler([.banner, .sound])
            return
        }

        // Mark this medication as active for the widget
        if let medName = notification.request.content.userInfo["medicationName"] as? String, !medName.isEmpty {
            var active = SharedState.activeMedicationNames
            if !active.contains(medName) {
                active.append(medName)
            }
            SharedState.activeMedicationNames = active
            SharedState.hasActiveAlarm = true
        }

        // Start continuous haptics (repeats until dismissed/snoozed)
        startRepeatingHaptics()

        // Always trigger AlarmPlayer sound for every notification (initial and re-nags).
        let soundName = notification.request.content.userInfo["soundName"] as? String ?? "pebble"
        let sound = NagRXSound(rawValue: soundName) ?? .pebble
        AlarmPlayer.shared.playSoundDirectly(sound)

        // Infinite chain: schedule another re-nag notification in the future
        // so alerts never stop until the user dismisses.
        scheduleNextReNag(from: notification.request)

        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        let notif = response.notification
        guard notif.request.content.categoryIdentifier == AlarmAction.category else { return }

        switch response.actionIdentifier {
        case AlarmAction.snooze:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content, minutes: 15)

        case AlarmAction.snooze90:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content, minutes: 90)

        case AlarmAction.snoozeDay:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content, minutes: 24 * 60)

        case UNNotificationDefaultActionIdentifier:
            let base = stripAlarmSuffix(notif.request.identifier)
            snoozeAlarm(base: base, content: notif.request.content, minutes: 15)

        case AlarmAction.dismiss, UNNotificationDismissActionIdentifier:
            let base = stripAlarmSuffix(notif.request.identifier)
            dismissAlarm(base: base, content: notif.request.content)

        default:
            break
        }
    }

    // MARK: Alarm Helpers

    private func stripAlarmSuffix(_ identifier: String) -> String {
        var result = identifier
        // Strip re-nag suffixes (_r1, _r2, ... _r999, _snooze)
        if let range = result.range(of: "_r\\d+$", options: .regularExpression) {
            result.removeSubrange(range)
        }
        result = result.replacingOccurrences(of: "_snooze", with: "")
        // Strip occurrence suffix (e.g., "_occ0", "_occ1")
        if let range = result.range(of: "_occ\\d+$", options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    /// Schedules the next re-nag notification to keep the chain going indefinitely.
    private func scheduleNextReNag(from request: UNNotificationRequest) {
        let intervalSeconds = Double(AppSettings.shared.reNagIntervalMinutes) * 60
        let content = request.content

        // Determine next re-nag number
        let currentID = request.identifier
        let nextNumber: Int
        if let range = currentID.range(of: "_r(\\d+)$", options: .regularExpression) {
            let numStr = currentID[range].dropFirst(2) // drop "_r"
            nextNumber = (Int(numStr) ?? 0) + 1
        } else {
            nextNumber = 1
        }

        let baseID = stripAlarmSuffix(currentID)
        // Reconstruct with occurrence suffix if present
        let occPattern = try? NSRegularExpression(pattern: "_occ\\d+")
        let occMatch = occPattern?.firstMatch(in: currentID, range: NSRange(currentID.startIndex..., in: currentID))
        let occSuffix: String
        if let match = occMatch {
            occSuffix = String(currentID[Range(match.range, in: currentID)!])
        } else {
            occSuffix = ""
        }

        let nextID = baseID + occSuffix + "_r\(nextNumber)"

        let mutable = content.mutableCopy() as! UNMutableNotificationContent
        mutable.subtitle = "STILL WAITING: take your medication"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: intervalSeconds,
            repeats: false
        )
        let nextRequest = UNNotificationRequest(identifier: nextID, content: mutable, trigger: trigger)
        center.add(nextRequest) { error in
            if let error {
                print("[NagRX] Failed to schedule next re-nag \(nextID): \(error)")
            }
        }
    }

    private func dismissAlarm(base: String, content: UNNotificationContent) {
        cancel(identifiers: [base])
        stopHaptics()
        AlarmPlayer.shared.dismiss(identifier: base)

        let medName = content.userInfo["medicationName"] as? String ?? ""

        // Celebrate the user — strong haptic + visual overlay.
        // Action button has .foreground option so the app is active when this runs,
        // letting CoreHaptics actually fire and the overlay become visible.
        playSuccessHaptic()
        Task { @MainActor in
            CelebrationManager.shared.celebrate(medicationName: medName)
        }

        var active = SharedState.activeMedicationNames
        if !medName.isEmpty {
            active.removeAll { $0 == medName }
        }
        SharedState.activeMedicationNames = active
        SharedState.hasActiveAlarm = !active.isEmpty

        center.removeAllDeliveredNotifications()

        sendDismissToWatch()
    }

    private func snoozeAlarm(base: String, content: UNNotificationContent, minutes: Int) {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        let snoozeSeconds: TimeInterval = Double(minutes) * 60
        let snoozeID = base + "_snooze"

        let mutable = content.mutableCopy() as! UNMutableNotificationContent
        mutable.subtitle = "Snoozed — take your medication"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: snoozeSeconds,
            repeats: false
        )
        let request = UNNotificationRequest(identifier: snoozeID, content: mutable, trigger: trigger)
        center.add(request) { error in
            if let error { print("[NagRX] Snooze schedule failed: \(error)") }
        }

        stopHaptics()
        AlarmPlayer.shared.stopForSnooze(identifier: base)
        let snoozeDate = Date().addingTimeInterval(snoozeSeconds)
        let soundName = content.userInfo["soundName"] as? String ?? "pebble"
        let sound = NagRXSound(rawValue: soundName) ?? .pebble
        let medName = content.userInfo["medicationName"] as? String ?? ""
        AlarmPlayer.shared.addSnooze(identifier: base, at: snoozeDate, sound: sound, medicationName: medName)

        sendDismissToWatch()
    }

    /// Tell the Watch to cancel its alerts when user acts on the phone.
    private func sendDismissToWatch() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["action": "dismiss"]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil) { error in
                print("[NagRX] Failed to send dismiss to Watch: \(error)")
            }
        }
    }

    // MARK: Schedule helpers

    private func schedule(
        id: String,
        title: String,
        subtitle: String,
        threadID: String,
        date: Date,
        sound: NagRXSound,
        isSilent: Bool = false
    ) async {
        let content = UNMutableNotificationContent()
        content.title             = title
        content.subtitle          = subtitle
        content.threadIdentifier  = threadID
        content.interruptionLevel = .timeSensitive
        let medName = title.replacingOccurrences(of: "Take ", with: "")
        content.userInfo["medicationName"] = medName
        content.userInfo["silentReminder"] = isSilent

        if isSilent {
            content.body = ""
            content.sound = .default
        } else {
            content.body = "Long-press for options"
            content.sound = sound.notificationSound
            content.categoryIdentifier = AlarmAction.category
            content.userInfo["soundName"] = sound.rawValue
        }

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("[NagRX] Failed to schedule \(id): \(error)")
        }
    }

    // MARK: Haptics

    private func prepareHapticEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.resetHandler = { [weak self] in
                try? self?.hapticEngine?.start()
            }
            hapticEngine?.stoppedHandler = { _ in }
            try hapticEngine?.start()
        } catch {
            print("[NagRX] Haptic engine error: \(error)")
        }
    }

    /// Starts repeating haptic bursts that continue until stopHaptics() is called.
    /// Each burst is a 5-second aggressive staccato pattern, followed by a brief pause,
    /// then it repeats. This continues for up to 5 minutes total.
    func startRepeatingHaptics() {
        stopHaptics()

        // Fire the first burst immediately
        playOneHapticBurst()

        // Repeat every 5.5 seconds (5s burst + 0.5s gap) — nearly continuous
        let t = Timer(timeInterval: 5.5, repeats: true) { [weak self] _ in
            self?.playOneHapticBurst()
        }
        RunLoop.main.add(t, forMode: .common)
        hapticRepeatTimer = t

        // Auto-stop after 5 minutes
        let work = DispatchWorkItem { [weak self] in
            self?.stopHaptics()
        }
        hapticStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)
    }

    /// Plays a single 5-second burst of aggressive staccato haptics.
    /// Uses an on/off pulsing pattern that is more attention-getting than a constant buzz.
    private func playOneHapticBurst() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            // Fallback: UIKit heavy impacts for 5 seconds
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.prepare()
                // Pulsing pattern: heavy impact every 0.15s for 5 seconds
                for i in 0..<33 {
                    let t = Double(i) * 0.15
                    let item = DispatchWorkItem { gen.impactOccurred(intensity: 1.0) }
                    self.hapticFallbackItems.append(item)
                    DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: item)
                }
            }
            return
        }

        // Aggressive staccato pattern over 5 seconds:
        // Alternates between 0.3s of max-intensity buzz + transient hits,
        // then 0.1s of silence. The pulsing on/off feels much stronger
        // than a constant vibration because each onset is a fresh impact.
        var events: [CHHapticEvent] = []
        let burstDuration: TimeInterval = 5.0
        let onTime: TimeInterval = 0.3
        let offTime: TimeInterval = 0.1
        let cycleTime = onTime + offTime
        let transientStep: TimeInterval = 0.05  // transient hits within each on-period

        var t: TimeInterval = 0
        while t < burstDuration {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)

            // Continuous buzz for the on-period
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: t,
                duration: onTime
            ))

            // Layer transient hits throughout the on-period for extra punch
            var tt = t
            while tt < t + onTime && tt < burstDuration {
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: tt
                ))
                tt += transientStep
            }

            t += cycleTime
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = false
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            hapticPlayer = player
        } catch {
            print("[NagRX] Haptic playback error: \(error)")
        }
    }

    func stopHaptics() {
        hapticStopWork?.cancel()
        hapticStopWork = nil
        hapticRepeatTimer?.invalidate()
        hapticRepeatTimer = nil
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil

        hapticFallbackItems.forEach { $0.cancel() }
        hapticFallbackItems.removeAll()
    }

    /// Plays a noticeable celebratory haptic pattern for when the user marks a medication taken.
    /// Three escalating taps, a rising continuous buzz, then a final exclamation hit — the rhythm
    /// reads as "ta-da!" rather than the alarm's repeating staccato.
    /// No-op when the user has disabled celebrations in Settings.
    func playSuccessHaptic() {
        guard AppSettings.shared.celebrationEnabled else { return }
        // UIKit notification haptic plays alongside CoreHaptics for an extra-strong success "thunk".
        DispatchQueue.main.async {
            let gen = UINotificationFeedbackGenerator()
            gen.prepare()
            gen.notificationOccurred(.success)
        }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else {
            // Fallback: three escalating heavy impacts.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.prepare()
                let intensities: [(Double, CGFloat)] = [(0.0, 0.6), (0.12, 0.8), (0.28, 1.0), (0.55, 1.0)]
                for (delay, intensity) in intensities {
                    let item = DispatchWorkItem { gen.impactOccurred(intensity: intensity) }
                    self.hapticFallbackItems.append(item)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
                }
            }
            return
        }

        var events: [CHHapticEvent] = []

        // Three escalating taps — opens with attention-grabbing rhythm.
        let tapTimes: [(Double, Float)] = [(0.0, 0.7), (0.12, 0.85), (0.26, 1.0)]
        for (time, intensity) in tapTimes {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: time
            ))
        }

        // Rising continuous buzz (0.45s) using intensity curve for a "whoosh up" feel.
        let buzzStart: TimeInterval = 0.42
        let buzzDuration: TimeInterval = 0.45
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: buzzStart,
            duration: buzzDuration
        ))

        let intensityCurve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.4),
                .init(relativeTime: buzzDuration * 0.6, value: 1.0),
                .init(relativeTime: buzzDuration, value: 1.0)
            ],
            relativeTime: buzzStart
        )
        let sharpnessCurve = CHHapticParameterCurve(
            parameterID: .hapticSharpnessControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.3),
                .init(relativeTime: buzzDuration, value: 1.0)
            ],
            relativeTime: buzzStart
        )

        // Final exclamation hit.
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            ],
            relativeTime: buzzStart + buzzDuration + 0.03
        ))

        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: [intensityCurve, sharpnessCurve])
            try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = false
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            hapticPlayer = player
        } catch {
            print("[NagRX] Success haptic error: \(error)")
        }
    }
}
