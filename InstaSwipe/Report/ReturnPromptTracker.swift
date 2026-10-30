import Observation
import InstaSwipeKit
import SwiftUI

/// Remembers which account was just opened in the Instagram app and raises a "did you do it?" prompt
/// when the user comes back. Shared by the report list and the swipe screen.
@MainActor
@Observable
final class ReturnPromptTracker {
    struct Pending: Equatable {
        let username: String
        let mode: ListMode
    }

    /// Account just opened in Instagram; the prompt waits for the app to come back.
    private(set) var pending: Pending?
    /// What the "did you do it?" sheet is about; non-nil while the sheet is shown.
    private(set) var prompt: Pending?

    @ObservationIgnored private var hasLeftApp = false

    /// Call right before opening Instagram; `nil` means this open needs no prompt.
    func willOpen(_ pending: Pending?) {
        self.pending = pending
        hasLeftApp = false
    }

    /// The `.active` that fires right after the tap is ignored: the prompt needs a real round trip.
    func scenePhaseChanged(_ phase: ScenePhase) {
        guard pending != nil else { return }
        switch phase {
        case .inactive, .background:
            hasLeftApp = true
        case .active:
            guard hasLeftApp else { return }
            prompt = pending
            pending = nil
            hasLeftApp = false
        @unknown default:
            break
        }
    }

    func dismiss() {
        prompt = nil
    }
}
