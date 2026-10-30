import InstaSwipeKit
import SwiftUI

/// Bottom of the profile page opened by "Togli il follow subito": how to unfollow, today's count, and "Fatto".
/// The unfollow itself stays a tap on Instagram's own button.
struct UnfollowBar: View {
    let unfollowsToday: Int
    let isOverDailyWarning: Bool
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tocca Segui già › Smetti di seguire")
                    .font(.outfit(14, .medium))
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Text("Oggi: \(unfollowsToday)")
                    .font(.outfit(14, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isOverDailyWarning ? Theme.warningText : Theme.ink)
                    .accessibilityIdentifier("unfollowBarCounter")
            }
            if isOverDailyWarning {
                DailyLimitWarning()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Fatto, non lo seguo più", action: onDone)
                .buttonStyle(GradientButtonStyle(height: 50))
                .accessibilityIdentifier("unfollowDoneButton")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }
}
