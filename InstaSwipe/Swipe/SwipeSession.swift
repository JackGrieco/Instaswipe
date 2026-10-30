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
    }

    static let maxLoadsInFlight = 2
    static let scopeDefaultsKey = "swipeScope"
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
    /// Bumped each time closing an unfollow page without "Fatto" puts the card back; the card screen animates it.
    private(set) var revertedUnfollowCount = 0
    /// The side the reverted card left from. Set in the same transaction as the revert, so the card built for
    /// the restored account already knows how to slide in; the screen clears it once the card appears.
    private(set) var revertedEntryDecision: Decision?
    /// A view preference, not review data: kept in `UserDefaults`, outside `AppState` and its iCloud mirror.
    private(set) var scope: ReviewScope {
        didSet {
            defaults.set(scope.rawValue, forKey: Self.scopeDefaultsKey)
            loadVisibleProfiles()
        }
    }

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
        scope = defaults.string(forKey: Self.scopeDefaultsKey).flatMap(ReviewScope.init(rawValue:)) ?? .everyone
    }

    // MARK: State

    /// The "Solo chi non ti segue" switch.
    var isNotFollowingBackOnly: Bool {
        get { scope == .notFollowingBack }
        set { scope = newValue ? .notFollowingBack : .everyone }
    }

    /// The filter emptied the queue, but accounts that follow you back are still waiting.
    var hasOthersToReview: Bool {
        guard scope != .everyone, let state = model.state else { return false }
        return Review.current(in: state) != nil
    }

    var current: FollowedAccount? { model.state.flatMap { Review.current(in: $0, scope: scope) } }

    var currentResult: ProfilePageResult? { current.flatMap { results[$0.username] } }

    /// The card waiting behind the current one.
    var next: FollowedAccount? {
        guard let state = model.state, let current else { return nil }
        return Review.next(after: current.username, in: state, scope: scope)
    }

    func imageURL(for username: String) -> URL? {
        if case .profile(_, let url) = results[username] { return url }
        return nil
    }

    /// What `undo` would revert, so the card can come back from the side it left.
    var lastDecision: Decision? { model.state.flatMap { Review.lastDecided(in: $0, scope: scope)?.decision } }

    var progressFraction: Double {
        guard let state = model.state else { return 0 }
        let progress = Review.progress(in: state, scope: scope)
        return progress.total > 0 ? Double(progress.decided) / Double(progress.total) : 0
    }

    var canUndo: Bool { lastDecision != nil }

    var budgetStatus: BudgetStatus {
        guard let state = model.state else { return .limitReached }
        return ProfileBudget.status(in: state, now: now(), calendar: calendar)
    }

    var screen: Screen {
        guard let current else { return .finished }
        let status = budgetStatus
        if case .available = status { return .card }
        let hasProfileData = results[current.username] != nil || inFlight.contains(current.username)
        return isOfflineSession || hasProfileData ? .card : .limit(status)
    }

    var reviewCounts: (kept: Int, toRemove: Int, gone: Int) {
        guard let state = model.state else { return (0, 0, 0) }
        let counts = Report.counts(in: state)
        return (counts[.kept] ?? 0, counts[.toDo] ?? 0, counts[.gone] ?? 0)
    }

    var isInstantUnfollowEnabled: Bool { defaults.bool(forKey: Self.instantUnfollowDefaultsKey) }

    var unfollowsToday: Int {
        model.state.map { Report.unfollowsToday(in: $0, now: now(), calendar: calendar) } ?? 0
    }

    var isOverDailyUnfollowWarning: Bool { unfollowsToday >= Limits.dailyUnfollowWarning }

    // MARK: Labels

    var progressLabel: String {
        let progress = model.state.map { Review.progress(in: $0, scope: scope) } ?? ReviewProgress(decided: 0, total: 0)
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
        model.apply { Review.decide(decision, username: username, in: $0, now: date) }
        loadVisibleProfiles()
        let account = model.state?.accounts.first { $0.username == username }
        let isApplied = account?.decision == decision && account?.decidedAt == date
        if isApplied, decision == .remove, isInstantUnfollowEnabled, openProfilePage(username) {
            unfollowUsername = username
        }
        return isApplied
    }

    func undo() {
        let scope = scope
        model.apply { Review.undo(in: $0, scope: scope) }
        loadVisibleProfiles()
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
        guard !isOfflineSession, let current, let state = model.state else { return }
        var visible = [current.username]
        if let next = Review.next(after: current.username, in: state, scope: scope) { visible.append(next.username) }
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
            model.apply { Review.markAvailability(.available, displayName: displayName, username: username, in: $0) }
            if let imageURL { Task { await thumbnails.store(from: imageURL, username: username) } }
        case .unavailable:
            results[username] = result
            model.apply { Review.markAvailability(.unavailable, displayName: nil, username: username, in: $0) }
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
