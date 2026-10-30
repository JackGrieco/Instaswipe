import Foundation
import InstaSwipeKit

/// What `AppModel.confirmRestore()` changes: only the lists whose file could not be read.
/// A readable file of the other list is left exactly as it is.
struct RestorePlan: Equatable, Sendable {
    /// From the newest readable backup; nil when state.json is readable and stays.
    let state: AppState?
    /// From the newest backup holding followers; nil when followers.json stays as it is.
    let followers: FollowerState?
    /// followers.json is unreadable and no backup holds followers: its quarantined copies are
    /// renamed (never deleted) so they stop blocking the app, and the follower list starts empty.
    let discardsFollowers: Bool

    var isEmpty: Bool { state == nil && followers == nil && !discardsFollowers }

    var title: String {
        guard let date = state?.savedAt ?? followers?.savedAt else {
            return "Mettere da parte i follower illeggibili?"
        }
        return "Ripristinare la copia del \(date.formatted(date: .abbreviated, time: .shortened))?"
    }

    var message: String {
        let followingLine = state.map { "Following: \(Self.decisions(in: $0.accounts)) decisioni dalla copia." }
            ?? "I following restano come sono."
        let followersLine = followers.map { "Follower: \(Self.decisions(in: $0.accounts)) decisioni dalla copia." }
            ?? (discardsFollowers
                ? "Non ho una copia dei follower: reimporta l'export per ritrovarli."
                : "I follower restano come sono.")
        return [followingLine, followersLine, "I file illeggibili restano da parte."].joined(separator: " ")
    }

    private static func decisions(in accounts: [FollowedAccount]) -> Int {
        accounts.filter { $0.decision != .pending }.count
    }
}
