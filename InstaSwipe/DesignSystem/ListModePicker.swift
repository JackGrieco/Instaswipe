import InstaSwipeKit
import SwiftUI

/// "Following" / "Follower" switch shown on every swipe screen and above the "Da togliere" list.
struct ListModePicker: View {
    @Binding var mode: ListMode
    var isDisabled = false

    var body: some View {
        Picker("Lista", selection: $mode) {
            Text("Following").tag(ListMode.following)
            Text("Follower").tag(ListMode.followers)
        }
        .pickerStyle(.segmented)
        .disabled(isDisabled)
        .accessibilityIdentifier("listModePicker")
    }
}
