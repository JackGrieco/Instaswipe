import SwiftUI

/// Follower mode before any followers file was imported.
struct NoFollowersView: View {
    @Environment(SettingsPresenter.self) private var settings

    var body: some View {
        VStack(spacing: 12) {
            Text("Nessun follower importato")
                .font(.outfit(26, .bold))
                .tracking(-0.01, size: 26)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Per ripulire chi ti segue, importa di nuovo l'export di Instagram: questa volta leggo anche i follower.")
                .font(.outfit(15))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            Button("Reimporta export") { settings.isPresented = true }
                .buttonStyle(GradientButtonStyle())
                .padding(.top, 20)
                .accessibilityIdentifier("reimportButton")
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
