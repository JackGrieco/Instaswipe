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
    /// The state and the followers come from two different backups (an older one held the
    /// followers): the text then shows both dates.
    let isFromTwoBackups: Bool

    init(state: AppState?, followers: FollowerState?, discardsFollowers: Bool, isFromTwoBackups: Bool = false) {
        self.state = state
        self.followers = followers
        self.discardsFollowers = discardsFollowers
        self.isFromTwoBackups = isFromTwoBackups
    }

    var isEmpty: Bool { state == nil && followers == nil && !discardsFollowers }

    var title: String {
        if isFromTwoBackups { return "Ripristinare le copie di sicurezza?" }
        guard let date = state?.savedAt ?? followers?.savedAt else {
            return "Mettere da parte i follower illeggibili?"
        }
        return "Ripristinare la copia del \(Self.text(date))?"
    }

    var message: String {
        let followingLine = state.map { "Following: \(Self.decisions(in: $0.accounts)) decisioni \(source($0.savedAt))." }
            ?? "I following restano come sono."
        let followersLine = followers.map { "Follower: \(Self.decisions(in: $0.accounts)) decisioni \(source($0.savedAt))." }
            ?? (discardsFollowers
                ? "Non ho una copia dei follower: reimporta l'export per ritrovarli."
                : "I follower restano come sono.")
        return [followingLine, followersLine, "I file illeggibili restano da parte."].joined(separator: " ")
    }

    /// With one backup the title already has its date; with two, each line names its own.
    private func source(_ date: Date) -> String {
        isFromTwoBackups ? "dalla copia del \(Self.text(date))" : "dalla copia"
    }

    private static func text(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func decisions(in accounts: [FollowedAccount]) -> Int {
        accounts.filter { $0.decision != .pending }.count
    }
}
