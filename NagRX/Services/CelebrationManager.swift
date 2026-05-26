import Foundation
import SwiftUI

/// Observable bus for celebrating when a medication is marked taken.
/// ContentView observes this and overlays the celebration animation when `isCelebrating` flips true.
@MainActor
@Observable
final class CelebrationManager {
    static let shared = CelebrationManager()

    var isCelebrating: Bool = false
    var medicationName: String = ""

    @ObservationIgnored private var dismissWork: DispatchWorkItem?

    private init() {}

    /// Trigger the celebration overlay. Auto-dismisses after ~2.4s.
    /// No-op when the user has disabled celebrations in Settings.
    func celebrate(medicationName: String = "") {
        guard AppSettings.shared.celebrationEnabled else { return }
        self.medicationName = medicationName
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            isCelebrating = true
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.35)) {
                self?.isCelebrating = false
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }
}
