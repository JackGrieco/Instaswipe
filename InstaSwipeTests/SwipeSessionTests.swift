import Foundation
import InstaSwipeKit
import Testing
@testable import InstaSwipe

/// Loader whose results are completed by hand, so tests control ordering.
@MainActor
final class ManualProfileLoader: ProfileLoading {
    private(set) var calls: [String] = []
    private var pending: [String: CheckedContinuation<ProfilePageResult, Never>] = [:]

    func load(username: String) async -> ProfilePageResult {
        calls.append(username)
        return await withCheckedContinuation { pending[username] = $0 }
    }

    func complete(_ username: String, with result: ProfilePageResult) {
        pending.removeValue(forKey: username)?.resume(returning: result)
    }
}

@MainActor
struct SwipeSessionTests {
    private let usernames = ["aa", "bb", "cc", "dd", "ee"]

    private func makeSession(
        limit: Int? = nil,
        loader: ManualProfileLoader = ManualProfileLoader()
    ) throws -> (SwipeSession, AppModel, ManualProfileLoader) {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        var state = AppState.empty(now: Date())
        state.accounts = usernames.enumerated().map { index, name in
            FollowedAccount(
                username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
                followedSince: Date(timeIntervalSince1970: 1_600_000_000 + Double(index))
            )
        }
        if let limit { state.dailyProfileLimit = limit }
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
        let environment = AppEnvironment(
            localDirectory: local, cloudDirectory: nil, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false
        )
        let model = AppModel(environment: environment)
        return (SwipeSession(model: model, loader: loader), model, loader)
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func account(_ name: String, in model: AppModel) -> FollowedAccount? {
        model.state?.accounts.first { $0.username == name }
    }

    @Test func neverMoreThanTwoInFlightAndNoDuplicates() async throws {
        let (session, _, loader) = try makeSession()
        session.start()
        session.start()
        await settle()
        #expect(loader.calls == ["aa", "bb"])

        session.decide(.keep)
        await settle()
        #expect(loader.calls == ["aa", "bb"])
        #expect(session.inFlight.count == 2)

        loader.complete("aa", with: .profile(displayName: "A", imageURL: nil))
        await settle()
        #expect(loader.calls == ["aa", "bb", "cc"])
    }

    @Test func limitReachedMakesNoLoaderCall() async throws {
        let (session, _, loader) = try makeSession(limit: 0)
        session.start()
        await settle()
        #expect(loader.calls.isEmpty)
        #expect(session.screen == .limit(.limitReached))
    }

    @Test func rateLimitedRecordsEmergencyStopAndStopsLoading() async throws {
        let (session, model, loader) = try makeSession()
        session.start()
        await settle()

        loader.complete("aa", with: .rateLimited)
        await settle()
        loader.complete("bb", with: .profile(displayName: nil, imageURL: nil))
        await settle()

        #expect(model.state?.emergencyStopDay != nil)
        #expect(loader.calls == ["aa", "bb"])
        #expect(session.screen == .limit(.emergencyStopped))
    }

    @Test func unavailableCurrentIsMarkedAndSkipped() async throws {
        let (session, model, loader) = try makeSession()
        session.start()
        await settle()

        loader.complete("aa", with: .unavailable)
        await settle()

        #expect(account("aa", in: model)?.availability == .unavailable)
        #expect(session.current?.username == "bb")
        #expect(loader.calls == ["aa", "bb", "cc"])
    }

    @Test func profileArrivingAfterDecisionKeepsTheDecision() async throws {
        let (session, model, loader) = try makeSession()
        session.start()
        await settle()
        session.decide(.remove)

        loader.complete("aa", with: .profile(displayName: "Late", imageURL: nil))
        await settle()

        #expect(account("aa", in: model)?.decision == .remove)
        #expect(account("aa", in: model)?.availability == .available)
        #expect(account("aa", in: model)?.displayName == "Late")
        #expect(session.current?.username == "bb")
    }

    @Test func offlineSessionNeverCallsTheLoader() async throws {
        let (session, _, loader) = try makeSession()
        session.isOfflineSession = true
        session.start()
        session.decide(.keep)
        session.undo()
        await settle()
        #expect(loader.calls.isEmpty)
        #expect(session.screen == .card)
        session.requestProfilePage()
        #expect(session.profilePageURL == nil)
    }

    @Test func loginRequiredPresentsLoginAndRetriesAfterDismissal() async throws {
        let (session, _, loader) = try makeSession()
        session.start()
        await settle()
        loader.complete("aa", with: .loginRequired)
        await settle()
        #expect(session.isLoginPresented)

        session.loginDismissed()
        await settle()
        #expect(loader.calls == ["aa", "bb", "aa"])
    }

    @Test func labelsUseItalianFormatting() async throws {
        let (session, _, _) = try makeSession()
        #expect(session.progressLabel == "0 / 5")
        #expect(session.profilesTodayLabel == "Profili oggi: 0 / 400")
        #expect(SwipeSession.groupedNumber(1240) == "1.240")
    }

    @Test func nextIsTheCardBehindTheCurrentOne() async throws {
        let (session, _, _) = try makeSession()
        #expect(session.next?.username == "bb")
        session.decide(.keep)
        #expect(session.next?.username == "cc")
    }

    @Test func imageURLComesFromTheLoadedProfile() async throws {
        let (session, _, loader) = try makeSession()
        let url = URL(string: "https://example.com/bb.jpg")!
        session.start()
        await settle()

        loader.complete("bb", with: .profile(displayName: "B", imageURL: url))
        await settle()

        #expect(session.imageURL(for: "bb") == url)
        #expect(session.imageURL(for: "aa") == nil)
    }

    @Test func unsureCardComesBackAfterTheOthers() async throws {
        let (session, _, _) = try makeSession()

        #expect(session.decide(.unsure))
        #expect(session.current?.username == "bb")
        for _ in 0..<4 { session.decide(.keep) }

        #expect(session.current?.username == "aa")
        #expect(session.decide(.unsure))
        #expect(session.current?.username == "aa")
        #expect(session.decide(.remove))
        #expect(session.screen == .finished)
    }

    @Test func lastDecisionAndProgressFollowTheDecisions() async throws {
        let (session, _, _) = try makeSession()
        #expect(session.lastDecision == nil)
        #expect(session.progressFraction == 0)

        session.decide(.remove)

        #expect(session.lastDecision == .remove)
        #expect(session.progressFraction == 0.2)
    }
}

@MainActor
struct GroupedNumberTests {
    @Test func groupsThousandsWithDots() {
        #expect(SwipeSession.groupedNumber(0) == "0")
        #expect(SwipeSession.groupedNumber(999) == "999")
        #expect(SwipeSession.groupedNumber(5622) == "5.622")
        #expect(SwipeSession.groupedNumber(1_234_567) == "1.234.567")
    }
}
