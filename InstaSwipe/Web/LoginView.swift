import SwiftUI

struct LoginView: View {
    private static let loginURL = URL(string: "https://www.instagram.com/accounts/login/")!
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebView(url: Self.loginURL)
                .navigationTitle("Instagram")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Fatto") { dismiss() } }
                }
        }
    }
}
