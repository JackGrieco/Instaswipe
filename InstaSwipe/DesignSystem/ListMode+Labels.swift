import InstaSwipeKit

/// Every text that changes with the active list, in one place.
extension ListMode {
    /// Before the follow date on a card: "Ti segue dal 3 mar 2021".
    var sinceLabel: String {
        switch self {
        case .following: "Lo segui dal"
        case .followers: "Ti segue dal"
        }
    }

    /// Card badge when the other list links back.
    var followsBackBadge: String {
        switch self {
        case .following: "Ti segue"
        case .followers: "Lo segui"
        }
    }

    /// Row tag in "Da togliere" when the other list links back.
    var followsBackTag: String {
        switch self {
        case .following: "ti segue"
        case .followers: "lo segui"
        }
    }

    /// The swipe filter switch.
    var notFollowingBackFilter: String {
        switch self {
        case .following: "Solo chi non ti segue"
        case .followers: "Solo chi non segui"
        }
    }

    /// End screen when that filter emptied the queue.
    var filterFinishedMessage: String {
        switch self {
        case .following: "Hai rivisto tutti quelli che non ti seguono."
        case .followers: "Hai rivisto tutti quelli che non segui."
        }
    }

    /// End screen button that turns the filter off.
    var showEveryoneButton: String {
        switch self {
        case .following: "Mostra anche chi ti segue"
        case .followers: "Mostra anche chi segui"
        }
    }

    /// Start of the CSV file name, before the date.
    var csvFilePrefix: String {
        switch self {
        case .following: "InstaSwipe"
        case .followers: "InstaSwipe-follower"
        }
    }

    /// The "did you do it?" question after coming back from Instagram.
    func returnPromptTitle(for username: String) -> String {
        switch self {
        case .following: "Hai tolto il follow a @\(username)?"
        case .followers: "Hai rimosso @\(username) dai follower?"
        }
    }
}
