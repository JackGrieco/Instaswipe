import SwiftUI

/// Shown when the daily profile budget is used up or Instagram asked to slow down.
struct LimitReachedView: View {
    let isEmergencyStop: Bool
    let profilesTodayLabel: String
    let progressLabel: String
    let onContinueOffline: () -> Void
    @State private var isConfirming = false

    private var message: String {
        isEmergencyStop
            ? "Instagram ha chiesto di rallentare: ci fermiamo fino a domani"
            : "Per oggi basta, riprendi domani"
    }

    var body: some View {
        VStack(spacing: 0) {
            moon
            Text(message)
                .font(.outfit(26, .bold))
                .tracking(-0.01, size: 26)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            Text(profilesTodayLabel).padding(.top, 10)
            Text(progressLabel).padding(.top, 6)
            Button("Continua senza profili") { isConfirming = true }
                .buttonStyle(OutlineCapsuleButtonStyle())
                .padding(.top, 36)
        }
        .font(.outfit(15))
        .monospacedDigit()
        .foregroundStyle(Theme.ink2)
        .padding(.horizontal, 36)
        .riseIn()
        .confirmationDialog(
            "Continuare senza foto e nomi?", isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button("Continua senza profili", action: onContinueOffline)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Vedrai solo username e data, senza caricare i profili da Instagram.")
        }
    }

    private var moon: some View {
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: 56))
            .foregroundStyle(Theme.purple)
            .frame(width: 128, height: 128)
            .background(
                Circle().fill(EllipticalGradient(
                    stops: [
                        .init(color: Theme.purple.opacity(0.22), location: 0),
                        .init(color: Theme.pink.opacity(0.10), location: 0.6),
                        .init(color: .clear, location: 0.72)
                    ],
                    center: UnitPoint(x: 0.35, y: 0.3)
                ))
            )
            .accessibilityHidden(true)
    }
}

struct SwipeEndView: View {
    let kept: Int
    let toRemove: Int
    let gone: Int
    let onShowToRemove: () -> Void
    /// Set when the "Solo chi non ti segue" filter emptied the queue while followers are still to review.
    var onShowEveryone: (() -> Void)?

    @State private var hasBurst = false

    var body: some View {
        VStack(spacing: 0) {
            badge
            Text("Hai finito!")
                .font(.outfit(32, .bold))
                .tracking(-0.02, size: 32)
                .foregroundStyle(Theme.ink)
                .padding(.top, 22)
                .riseIn(delay: 0.1)
            if onShowEveryone != nil {
                Text("Hai rivisto tutti quelli che non ti seguono.")
                    .font(.outfit(15))
                    .foregroundStyle(Theme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .riseIn(delay: 0.15)
            }
            HStack(spacing: 10) {
                statTile(kept, label: "Tenuti", color: Theme.green)
                statTile(toRemove, label: "Da togliere", color: Theme.red)
                statTile(gone, label: "Spariti", color: Theme.ink2)
            }
            .padding(.top, 28)
            .riseIn(delay: 0.2)
            Button("Vai a Da togliere", action: onShowToRemove)
                .buttonStyle(GradientButtonStyle())
                .padding(.top, 32)
                .riseIn(delay: 0.3)
            if let onShowEveryone {
                Button("Mostra anche chi ti segue", action: onShowEveryone)
                    .buttonStyle(OutlineCapsuleButtonStyle())
                    .padding(.top, 14)
                    .riseIn(delay: 0.35)
                    .accessibilityIdentifier("showEveryoneButton")
            }
        }
        .padding(.horizontal, 28)
    }

    /// Green check that pops in: scale 0.4 → 1.08 → 1.
    private var badge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 104, height: 104)
            .background(Circle().fill(LinearGradient(
                colors: [Theme.greenLight, Theme.green], startPoint: .topLeading, endPoint: .bottomTrailing
            )))
            .shadow(color: Theme.green.opacity(0.4), radius: 18, y: 16)
            .scaleEffect(hasBurst ? 1 : 0.4)
            .opacity(hasBurst ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { hasBurst = true }
            }
            .accessibilityHidden(true)
    }

    private func statTile(_ value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(SwipeSession.groupedNumber(value))
                .font(.outfit(24, .bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.outfit(13))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .themeShadow()
        .accessibilityElement(children: .combine)
    }
}
