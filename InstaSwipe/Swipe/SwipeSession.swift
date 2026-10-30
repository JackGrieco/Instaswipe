import Foundation
import InstaSwipeKit
import Observation

/// Drives the swipe screen: decisions plus budget-aware profile loading for the current card and the next one.
@MainActor
@Observable
final class SwipeSession {
    enum Screen: Equatable {
        case finished
        case limit(BudgetStatus)
        case card
        /// Follower mode before any followers file was imported.
        case noFollowers
    }

    static let maxLoadsInFlight = 2
    static let scopeDefaultsKey = "swipeScope"
    static let followerScopeDefaultsKey = "followerSwipeScope"
    /// The "Togli il follow subito" switch in Settings: a remove opens the profile to unfollow by hand.
    static let instantUnfollowDefaultsKey = "instantUnfollow"

    private(set) var results: [String: ProfilePageResult] = [:]
    private(set) var inFlight: Set<String> = []
    /// Not persisted: "Continua senza profili" lasts until the app is closed.
    var isOfflineSession = false
    var isLoginPresented = false
    var isLimitAlertPresented = false
    private(set) var profilePageURL: URL?
    /// Set when the open profile page is there to unfollow that account, not just to look at it.
    private(set) var unfollowUsername: String?
    /// Follower mode: the Instagram app link to open for a removal. The view opens it and calls `appHandoffOpened()`.
    private(set) var appHandoffURL: URL?
    let returnPrompt = ReturnPromptTracker()
    /// Bumped each time closing an unfollow page without "Fatto" puts the card back; the card screen animates it.
    private(set) var revertedUnfollowCount = 0
    /// The side the reverted card left from. Set in the same transaction as the revert, so the card built for
    /// the restored account already knows how to slide in; the screen clears it once the card appears.
    private(set) var revertedEntryDecision: Decision?
    /// View preferences, not review data: kept in `UserDefaults`, outside the saved lists and their iCloud mirror.
    private var scopes: [ListMode: ReviewScope]

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let loader: any ProfileLoading
    @ObservationIgnored private let thumbnails: ThumbnailCache
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let defaults: UserDefaults

    init(
        model: AppModel,
        loader: any ProfileLoading,
        thumbnails: ThumbnailCache = ThumbnailCache(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.loader = loader
        self.thumbnails = thumbnails
        self.now = now
        self.calendar = calendar
        self.defaults = defaults
        scopes = Dictionary(uniqueKeysWithValues: ListMode.allCases.map { mode in
            (mode, defaults.string(forKey: Self.scopeKey(for: mode)).flatMap(ReviewScope.init(rawValue:)) ?? .everyone)
        })
    }

    private static func scopeKey(for mode: ListMode) -> String {
        switch mode {
        case .following: scopeDefaultsKey
        case .followers: followerScopeDefaultsKey
        }
    }

    // MARK: Mode

    /// The list being swiped; shared with the rest of the app through `AppModel.listMode`.
    var mode: ListMode {
        get { model.listMode }
        set {
            guard newValue != model.listMode else { return }
            model.listMode = newValue
            loadVisibleProfiles()
        }
    }

    private var list: AccountList? { model.list(mode) }

    private(set) var scope: ReviewScope {
        get { scopes[mode] ?? .everyone }
        set {
            let mode = mode
            scopes[mode] = newValue
            defaults.set(newValue.rawValue, forKey: Self.scopeKey(for: mode))
            loadVisibleProfiles()
        }
    }

    // MARK: State

    /// The "Solo chi non ti segue" switch.
    var isNotFollowingBackOnly: Bool {
        get { scope == .notFollowingBack }
        set { scope = newValue ? .notFollowingBack : .everyone }
    }

    /// The filter emptied the queue, but accounts that follow you back are still waiting.
    var hasOthersToReview: Bool {
        guard scope != .everyone, let list else { return false }
        return Review.current(in: list) != nil
    }

    var current: FollowedAccount? { list.flatMap { Review.current(in: $0, scope: scope) } }

    var currentResult: ProfilePageResult? { current.flatMap { results[$0.username] } }

    /// The card waiting behind the current one.
    var next: FollowedAccount? {
        guard let list, let current else { return nil }
        return Review.next(after: current.username, in: list, scope: scope)
    }

    func imageURL(for username: String) -> URL? {
        if case .profile(_, let url) = results[username] { return url }
        return nil
    }

    /// What `undo` would revert, so the card can come back from the side it left.
    var lastDecision: Decision? { list.flatMap { Review.lastDecided(in: $0, scope: scope)?.decision } }

    var progressFraction: Double {
        guard let list else { return 0 }
        let progress = Review.progress(in: list, scope: scope)
        return progress.total > 0 ? Double(progress.decided) / Double(progress.total) : 0
    }

    var canUndo: Bool { lastDecision != nil }

    var budgetStatus: BudgetStatus {
        guard let state = model.state else { return .limitReached }
        return ProfileBudget.status(in: state, now: now(), calendar: calendar)
    }

    var screen: Screen {
        if model.isAwaitingFollowerImport { return .noFollowers }
        guard let current else { return .finished }
        let status = budgetStatus
        if case .available = status { return .card }
        let hasProfileData = results[current.username] != nil || inFlight.contains(current.username)
        return isOfflineSession || hasProfileData ? .card : .limit(status)
    }

    var reviewCounts: (kept: Int, toRemove: Int, gone: Int) {
        guard let list else { return (0, 0, 0) }
        let counts = Report.counts(in: list)
        return (counts[.kept] ?? 0, counts[.toDo] ?? 0, counts[.gone] ?? 0)
    }

    var isInstantUnfollowEnabled: Bool { defaults.bool(forKey: Self.instantUnfollowDefaultsKey) }

    /// Unfollows plus follower removals marked done today.
    var unfollowsToday: Int { model.actionsToday(now: now(), calendar: calendar) }

    var isOverDailyUnfollowWarning: Bool { unfollowsToday >= Limits.dailyUnfollowWarning }

    // MARK: Labels

    var progressLabel: String {
        let progress = list.map { Review.progress(in: $0, scope: scope) } ?? ReviewProgress(decided: 0, total: 0)
        return "\(Self.groupedNumber(progress.decided)) / \(Self.groupedNumber(progress.total))"
    }

    var profilesTodayLabel: String {
        guard let state = model.state else { return "" }
        let isToday = calendar.isDate(state.profileLoads.day, inSameDayAs: now())
        return "Profili oggi: \(isToday ? state.profileLoads.count : 0) / \(state.dailyProfileLimit)"
    }

    /// Groups thousands with ".". NumberFormatter's it_IT skips grouping for 4-digit numbers (CLDR
    /// minimum-grouping rule), but the UI wants "1.240".
    static func groupedNumber(_ value: Int) -> String {
        let digits = String(abs(value))
        let grouped = digits.reversed().enumerated().reduce(into: "") { result, pair in
            if pair.offset > 0, pair.offset.isMultiple(of: 3) { result.append(".") }
            result.append(pair.element)
        }
        return (value < 0 ? "-" : "") + String(grouped.reversed())
    }

    // MARK: Actions

    func start() {
        loadVisibleProfiles()
    }

    /// Returns false when the decision was not applied (e.g. a failed save), so the card can return.
    @discardableResult
    func decide(_ decision: Decision) -> Bool {
        guard let username = current?.username else { return false }
        let date = now()
        let mode = mode
        model.apply(mode) { Review.decide(decision, username: username, in: $0, now: date) }
        loadVisibleProfiles()
        let account = model.list(mode)?.accounts.first { $0.username == username }
        let isApplied = account?.decision == decision && account?.decidedAt == date
        guard isApplied, decision == .remove, isInstantUnfollowEnabled, let account else { return isApplied }
        switch mode {
        case .following:
            if openProfilePage(username) { unfollowUsername = username }
        case .followers:
            // Removing a follower only works in the Instagram app, which costs no profile load.
            appHandoffURL = account.profileURL
            returnPrompt.willOpen(.init(username: username, mode: .followers))
        }
        return isApplied
    }

    func undo() {
        guard list != nil else { return }
        let scope = scope
        model.apply(mode) { Review.undo(in: $0, scope: scope) }
        loadVisibleProfiles()
    }

    func appHandoffOpened() {
        appHandoffURL = nil
    }

    /// "Yes" on the return prompt: done on the list the prompt was raised for, even after a mode switch.
    func confirmReturnPrompt() {
        if let prompt = returnPrompt.prompt {
            let date = now()
            model.apply(prompt.mode) { Report.setUnfollowed(true, username: prompt.username, in: $0, now: date) }
        }
        returnPrompt.dismiss()
    }

    /// "Changed my mind" on the return prompt.
    func keepFromReturnPrompt() {
        if let prompt = returnPrompt.prompt {
            let date = now()
            model.apply(prompt.mode) { Review.decide(.keep, username: prompt.username, in: $0, now: date) }
        }
        returnPrompt.dismiss()
    }

    /// Tap on the card: opening the real profile counts as a load in the budget.
    func requestProfilePage() {
        guard let username = current?.username else { return }
        openProfilePage(username)
    }

    /// "Fatto" on an instant-unfollow page: the user unfollowed on Instagram, so it leaves "Da fare".
    func confirmUnfollowed() {
        if let username = unfollowUsername {
            model.apply { Report.setUnfollowed(true, username: username, in: $0, now: now()) }
        }
        dismissProfilePage()
    }

    /// Closing an instant-unfollow page without "Fatto" undoes that swipe; a plain profile page just closes.
    func closeProfilePage() {
        if let username = unfollowUsername {
            let date = now()
            model.apply { Review.decide(.pending, username: username, in: $0, now: date) }
            revertedUnfollowCount += 1
            revertedEntryDecision = .remove
            loadVisibleProfiles()
        }
        dismissProfilePage()
    }

    func consumeRevertedEntry() {
        revertedEntryDecision = nil
    }

    private func dismissProfilePage() {
        profilePageURL = nil
        unfollowUsername = nil
    }

    func loginDismissed() {
        results = results.filter { $0.value != .loginRequired }
        loadVisibleProfiles()
    }

    // MARK: Loading

    /// Returns false when nothing opened: offline session, or today's budget is used up (the alert says so).
    @discardableResult
    private func openProfilePage(_ username: String) -> Bool {
        guard !isOfflineSession else { return false }
        guard case .available = budgetStatus else {
            isLimitAlertPresented = true
            return false
        }
        recordLoad()
        profilePageURL = URL(string: "https://www.instagram.com/\(username)/")
        return profilePageURL != nil
    }

    private func recordLoad() {
        model.apply { ProfileBudget.recordLoad(in: $0, now: now(), calendar: calendar) }
    }

    private func loadVisibleProfiles() {
        guard !isOfflineSession, let current, let list else { return }
        var visible = [current.username]
        if let next = Review.next(after: current.username, in: list, scope: scope) { visible.append(next.username) }
        for username in visible where results[username] == nil && !inFlight.contains(username) {
            guard inFlight.count < Self.maxLoadsInFlight, case .available = budgetStatus else { return }
            beginLoad(username)
        }
    }

    private func beginLoad(_ username: String) {
        recordLoad()
        inFlight.insert(username)
        // Never cancelled on swipe: the result is stored and applied whenever it arrives.
        Task {
            let result = await loader.load(username: username)
            finishLoad(username, result)
        }
    }

    private func finishLoad(_ username: String, _ result: ProfilePageResult) {
        inFlight.remove(username)
        switch result {
        case .profile(let displayName, let imageURL):
            results[username] = result
            model.applyToBothLists { Review.markAvailability(.available, displayName: displayName, username: username, in: $0) }
            if let imageURL { Task { await thumbnails.store(from: imageURL, username: username) } }
        case .unavailable:
            results[username] = result
            model.applyToBothLists { Review.markAvailability(.unavailable, displayName: nil, username: username, in: $0) }
        case .rateLimited:
            model.apply { ProfileBudget.recordEmergencyStop(in: $0, now: now(), calendar: calendar) }
        case .loginRequired:
            results[username] = result
            isLoginPresented = true
        case .unrecognized:
            results[username] = result
        }
        loadVisibleProfiles()
    }
}
