import SwiftUI
import SwiftData
import WatchConnectivity

@main
struct NagRXApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([Medication.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        NagScheduler.shared.configure(modelContainer: modelContainer)

        // Activate WatchConnectivity for syncing medications to Apple Watch
        if WCSession.isSupported() {
            WCSession.default.delegate = PhoneSessionDelegate.shared
            WCSession.default.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(modelContainer)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "nagrx", url.host == "takenow" else { return }

        // Capture which medication(s) were active before we clear them, so the celebration can name one.
        let celebratedName = SharedState.activeMedicationNames.first ?? ""

        // Clear the due doses' notifications; marking them taken below also
        // stops their alarms and re-alerts.
        NotificationService.shared.cancelAll()

        // Celebrate the user — strong haptic + visual confetti overlay.
        NotificationService.shared.playSuccessHaptic()
        Task { @MainActor in
            CelebrationManager.shared.celebrate(medicationName: celebratedName)
        }

        // Cancel Watch alerts too
        if WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable {
            WCSession.default.sendMessage(["action": "dismiss"], replyHandler: nil, errorHandler: nil)
        }

        // Record the due doses as taken and rebuild the schedule.
        Task { @MainActor in
            await NagScheduler.shared.markAllDueTaken()
        }
    }
}

// MARK: - PhoneSessionDelegate

/// Minimal WCSession delegate for the iOS side. Data flows one-way (iPhone → Watch).
final class PhoneSessionDelegate: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionDelegate()

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[NagRX] WCSession activation failed: \(error)")
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if message["request"] as? String == "sync" {
            print("[NagRX] Watch requested sync")
            Task { @MainActor in
                NagScheduler.shared.invalidateWatchPayloadCache()
                await NagScheduler.shared.sync()
            }
        } else if message["action"] as? String == "dismiss" {
            print("[NagRX] Watch dismissed alarm — cancelling phone alerts")
            DispatchQueue.main.async {
                let celebratedName = SharedState.activeMedicationNames.first ?? ""
                NotificationService.shared.cancelAll()
                NotificationService.shared.playSuccessHaptic()
                Task { @MainActor in
                    CelebrationManager.shared.celebrate(medicationName: celebratedName)
                }
                Task { @MainActor in
                    await NagScheduler.shared.markAllDueTaken()
                }
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
