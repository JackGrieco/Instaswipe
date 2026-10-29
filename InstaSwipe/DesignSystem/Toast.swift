import InstaSwipeKit
import SwiftUI

/// Short confirmation capsule shown at the top after an action ("Tenuto", "Annullato", …).
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let color: Color

    // Computed, not stored: every toast needs a fresh `id` so the same message can play twice in a row.
    static var kept: Toast { Toast(text: "Tenuto", color: Theme.green) }
    static var toRemove: Toast { Toast(text: "Da togliere", color: Theme.red) }
    static var undone: Toast { Toast(text: "Annullato", color: Theme.ink2) }
    static var markedDone: Toast { Toast(text: "Segnato come fatto", color: Theme.green) }
    static var keptAfterAll: Toast { Toast(text: "Lo tieni", color: Theme.green) }
    static var unsure: Toast { Toast(text: "Da rivedere", color: Theme.orange) }

    /// Confirmation for a swipe decision; nil for "Da decidere".
    static func after(_ decision: Decision) -> Toast? {
        switch decision {
        case .keep: .kept
        case .remove: .toRemove
        case .unsure: .unsure
        case .pending: nil
        }
    }
}

private struct ToastFrame {
    var opacity = 0.0
    var offsetY = 10.0
    var scale = 0.8
}

private struct ToastOverlay: ViewModifier {
    static let duration: Duration = .milliseconds(1200)

    @Binding var toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                label(toast)
                    .id(toast.id)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: Self.duration)
                        if self.toast?.id == toast.id { self.toast = nil }
                    }
            }
        }
    }

    /// Keyframes of the prototype's 1.2 s `isToast` animation: pop in, hold, drift up and fade.
    private func label(_ toast: Toast) -> some View {
        Text(toast.text)
            .font(.outfit(15, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(toast.color))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 10)
            .keyframeAnimator(initialValue: ToastFrame(), repeating: false) { view, frame in
                view.opacity(frame.opacity).offset(y: frame.offsetY).scaleEffect(frame.scale)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.17)
                    LinearKeyframe(1, duration: 0.77)
                    LinearKeyframe(0, duration: 0.26)
                }
                KeyframeTrack(\.offsetY) {
                    CubicKeyframe(0, duration: 0.17)
                    LinearKeyframe(0, duration: 0.77)
                    CubicKeyframe(-12, duration: 0.26)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.06, duration: 0.17)
                    CubicKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.65)
                    CubicKeyframe(0.96, duration: 0.26)
                }
            }
            .accessibilityAddTraits(.isStaticText)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastOverlay(toast: toast))
    }
}
