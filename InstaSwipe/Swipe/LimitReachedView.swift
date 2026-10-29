import SwiftUI

/// Shown when the daily profile budget is used up or Instagram asked to slow down.
struct LimitReachedView: View {
    let isEmergencyStop: Bool
    let onContinueOffline: () -> Void
    @State private var isConfirming = false

    private var message: String {
        isEmergencyStop
            ? "Instagram ha chiesto di rallentare: ci fermiamo fino a domani"
            : "Per oggi basta, riprendi domani"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(message).font(.title3.bold()).multilineTextAlignment(.center)
            Button("Continua senza profili") { isConfirming = true }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Continuare senza foto e nomi?", isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button("Continua senza profili", action: onContinueOffline)
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Vedrai solo username e data, senza caricare i profili da Instagram.")
        }
    }
}

struct SwipeEndView: View {
    let kept: Int
    let toRemove: Int
    let gone: Int
    let onShowToRemove: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Hai finito!").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Tenuti: \(kept)")
                Text("Da togliere: \(toRemove)")
                Text("Spariti: \(gone)")
            }
            Button("Vai a Da togliere", action: onShowToRemove).buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
