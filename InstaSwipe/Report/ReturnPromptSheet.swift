import SwiftUI

struct ReturnPromptSheet: View {
    let username: String
    let onConfirm: () -> Void
    let onNotYet: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Hai tolto il follow a @\(username)?")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Button("Sì, segna come fatto", action: onConfirm)
                .buttonStyle(.borderedProminent)
            Button("Non ancora", action: onNotYet)
                .buttonStyle(.bordered)
            Button("Ho cambiato idea, lo tengo", action: onKeep)
                .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(24)
        .presentationDetents([.height(300)])
    }
}
