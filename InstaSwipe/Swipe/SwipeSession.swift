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

    private(set) var results: [String: ProfilePageResult] = [:]
    private(set) var inFlight: Set<String> = []
    /// Not persisted: "Continua senza profili" lasts until the app is closed.
    var isOfflineSession = false
    var isLoginPresented = false
    var isLimitAlertPresented = false
    private(set) var profilePageURL: URL?

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let loader: any ProfileLoading
    @ObservationIgnored private let thumbnails: ThumbnailCache
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar

    init(
        model: AppModel,
        loader: any ProfileLoading,
        thumbnails: ThumbnailCache = ThumbnailCache(),
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.model = model
        self.loader = loader
        self.thumbnails = thumbnails
        self.now = now
        self.calendar = calendar
    }

    // MARK: State

    var current: FollowedAccount? { model.state.flatMap { Review.current(in: $0) } }

    var currentResult: ProfilePageResult? { current.flatMap { results[$0.username] } }

    var canUndo: Bool {
        model.state?.accounts.contains { $0.decision != .pending && $0.decidedAt != nil } ?? false
    }

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

    // MARK: Labels

    var progressLabel: String {
        let progress = model.state.map { Review.progress(in: $0) } ?? ReviewProgress(decided: 0, total: 0)
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

    func decide(_ decision: Decision) {
        guard let username = current?.username else { return }
        model.apply { Review.decide(decision, username: username, in: $0, now: now()) }
        loadVisibleProfiles()
    }

    func undo() {
        model.apply { Review.undo(in: $0) }
        loadVisibleProfiles()
    }

    /// Tap on the card: opening the real profile counts as a load in the budget.
    func requestProfilePage() {
        guard !isOfflineSession, let username = current?.username else { return }
        guard case .available = budgetStatus else {
            isLimitAlertPresented = true
            return
        }
        recordLoad()
        profilePageURL = URL(string: "https://www.instagram.com/\(username)/")
    }

    func closeProfilePage() {
        profilePageURL = nil
    }

    func loginDismissed() {
        results = results.filter { $0.value != .loginRequired }
        loadVisibleProfiles()
    }

    // MARK: Loading

    private func recordLoad() {
        model.apply { ProfileBudget.recordLoad(in: $0, now: now(), calendar: calendar) }
    }

    private func loadVisibleProfiles() {
        guard !isOfflineSession, let state = model.state, let current = Review.current(in: state) else { return }
        var visible = [current.username]
        if let next = Review.next(after: current.username, in: state) { visible.append(next.username) }
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
