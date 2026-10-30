import Foundation

/// Which list the app is reviewing: the accounts you follow, or the accounts that follow you.
public enum ListMode: String, Sendable, CaseIterable { case following, followers }

/// Anything `Review` and `Report` can work on: an ordered list of accounts plus the decision counter.
public protocol ReviewList: Sendable {
    var accounts: [FollowedAccount] { get set }
    var totalDecisionsMade: Int { get set }
}

/// Just the part of a state that review and report logic touches.
public struct AccountList: ReviewList, Equatable {
    public var accounts: [FollowedAccount]
    public var totalDecisionsMade: Int

    public init(accounts: [FollowedAccount], totalDecisionsMade: Int) {
        self.accounts = accounts
        self.totalDecisionsMade = totalDecisionsMade
    }
}

extension AppState: ReviewList {
    public var list: AccountList {
        get { AccountList(accounts: accounts, totalDecisionsMade: totalDecisionsMade) }
        set {
            accounts = newValue.accounts
            totalDecisionsMade = newValue.totalDecisionsMade
        }
    }
}
