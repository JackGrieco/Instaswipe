import Foundation
import InstaSwipeKit
import SwiftUI
import Testing
@testable import InstaSwipe

@MainActor
struct ReportSessionTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSession(
        accounts: [FollowedAccount]? = nil,
        followers: [FollowedAccount]? = nil
    ) throws -> (ReportSession, AppModel) {
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        var state = AppState.empty(now: fixedNow)
        state.accounts = accounts ?? defaultAccounts()
        try FileStateStore(localDirectory: local, cloudDirectory: nil).save(state)
        if let followers {
            var followerState = FollowerState.empty(now: fixedNow)
            followerState.accounts = followers
            try FollowerStore(localDirectory: local, cloudDirectory: nil).save(followerState)
        }
        let environment = AppEnvironment(
            localDirectory: local, cloudDirectory: nil, isUITesting: true,
            useFakeProfiles: true, shouldSeedTestAccounts: false,
            defaultsSuiteName: UUID().uuidString
        )
        let model = AppModel(environment: environment)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let session = ReportSession(model: model, now: { fixedNow }, calendar: calendar)
        return (session, model)
    }

    private func defaultAccounts() -> [FollowedAccount] {
        [
            makeAccount("aa", decision: .remove),
            makeAccount("bb", decision: .remove, done: true),
            makeAccount("cc", decision: .keep),
            makeAccount("dd", decision: .remove, availability: .unavailable),
            makeAccount("ee", decision: .pending)
        ]
    }

    private func makeAccount(
        _ name: String,
        decision: Decision,
        done: Bool = false,
        availability: Availability = .unknown
    ) -> FollowedAccount {
        FollowedAccount(
            username: name, profileURL: URL(string: "https://www.instagram.com/_u/\(name)")!,
            followedSince: Date(timeIntervalSince1970: 1_600_000_000), displayName: "Nome \(name)",
            availability: availability, decision: decision, decidedAt: fixedNow,
            unfollowedManually: done, unfollowedAt: done ? fixedNow : nil
        )
    }

    private func account(_ name: String, in model: AppModel) -> FollowedAccount? {
        model.state?.accounts.first { $0.username == name }
    }

    @Test func filterSelectsRowsAndLabelsCarryCounts() throws {
        let (session, _) = try makeSession()

        #expect(session.rows.map(\.username) == ["aa"])
        #expect(session.label(for: .toDo) == "Da fare (1)")
        #expect(session.label(for: .done) == "Fatti (1)")
        #expect(session.label(for: .gone) == "Spariti (1)")
        #expect(session.label(for: .kept) == "Tenuti (1)")
        #expect(session.label(for: .unsure) == "Dubbi (0)")
        #expect(ReportSession.title(for: .unsure) == "Dubbi")
        #expect(session.count(for: .toDo) == 1)
        session.filter = .kept
        #expect(session.rows.map(\.username) == ["cc"])
    }

    @Test func searchIgnoresFilterButSkipsPendingAccounts() throws {
        let (session, _) = try makeSession()
        session.filter = .kept

        session.searchText = "nome"

        #expect(session.rows.map(\.username) == ["aa", "bb", "cc", "dd"])
    }

    @Test func tickAndUntickUpdateTodayCounter() throws {
        let (session, model) = try makeSession()
        #expect(session.counterText == "Oggi: 1 azioni segnate")

        session.setUnfollowed(true, username: "aa")
        #expect(session.counterText == "Oggi: 2 azioni segnate")
        #expect(account("aa", in: model)?.unfollowedManually == true)

        session.setUnfollowed(false, username: "aa")
        session.setUnfollowed(false, username: "bb")
        #expect(session.counterText == "Oggi: 0 azioni segnate")
        #expect(!session.isOverDailyWarning)
    }

    @Test func counterWarnsFromThreshold() throws {
        let accounts = (0..<Limits.dailyUnfollowWarning).map {
            makeAccount("u\($0)", decision: .remove, done: true)
        }
        let (session, _) = try makeSession(accounts: accounts)

        #expect(session.isOverDailyWarning)
    }

    @Test func decideAndRetryChangeAccounts() throws {
        let (session, model) = try makeSession()

        session.decide(.keep, username: "aa")
        session.retryAvailability(username: "dd")

        #expect(account("aa", in: model)?.decision == .keep)
        #expect(account("dd", in: model)?.availability == .unknown)
    }

    @Test func retryAvailabilityResetsTheProfileInBothLists() throws {
        let (session, model) = try makeSession(followers: [makeAccount("dd", decision: .remove, availability: .unavailable)])

        session.retryAvailability(username: "dd")

        #expect(account("dd", in: model)?.availability == .unknown)
        #expect(model.followers?.accounts.first { $0.username == "dd" }?.availability == .unknown)
    }

    @Test func promptAppearsAfterReturningFromBackground() throws {
        let (session, _) = try makeSession()

        let url = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.inactive)
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        #expect(url.absoluteString == "https://www.instagram.com/_u/aa")
        #expect(session.promptUsername == "aa")
        #expect(session.returnPromptUsername == nil)
    }

    @Test func nonRemoveAccountOpensProfileWithoutPrompt() throws {
        let (session, _) = try makeSession()

        let url = session.open(makeAccount("cc", decision: .keep))
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        #expect(url.absoluteString == "https://www.instagram.com/_u/cc")
        #expect(session.returnPromptUsername == nil)
        #expect(session.promptUsername == nil)
    }

    @Test func openingKeepAccountClearsPreviousPendingPrompt() throws {
        let (session, _) = try makeSession()

        _ = session.open(makeAccount("aa", decision: .remove))
        _ = session.open(makeAccount("cc", decision: .keep))

        #expect(session.returnPromptUsername == nil)
    }

    @Test func noPromptWhenAppNeverLeft() throws {
        let (session, _) = try makeSession()

        _ = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.active)

        #expect(session.promptUsername == nil)
        #expect(session.returnPromptUsername == "aa")
    }

    @Test func confirmingPromptMarksDone() throws {
        let (session, model) = try makeSession()
        _ = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        session.confirmUnfollowed()

        #expect(account("aa", in: model)?.unfollowedManually == true)
        #expect(session.promptUsername == nil)
    }

    @Test func changingMindFromPromptKeepsAccount() throws {
        let (session, model) = try makeSession()
        _ = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        session.changeMindKeep()

        #expect(account("aa", in: model)?.decision == .keep)
        #expect(session.promptUsername == nil)
    }

    @Test func notYetLeavesAccountUntouched() throws {
        let (session, model) = try makeSession()
        let before = account("aa", in: model)
        _ = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        session.dismissPrompt()

        #expect(account("aa", in: model) == before)
        #expect(session.promptUsername == nil)
    }

    @Test func csvFileHasHeaderAllAccountsAndDatedName() throws {
        let (session, _) = try makeSession()

        let url = try session.writeCSV()

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.first == "username,link,data follow,decisione,fatto,ti segue")
        #expect(lines.count == 6)
        #expect(url.lastPathComponent == "InstaSwipe-2027-01-15.csv")
    }

    @Test func followerModeListsFollowers() throws {
        let (session, model) = try makeSession(followers: [
            makeAccount("f1", decision: .remove),
            makeAccount("f2", decision: .remove, done: true),
            makeAccount("f3", decision: .keep)
        ])
        model.listMode = .followers

        #expect(session.rows.map(\.username) == ["f1"])
        #expect(session.count(for: .done) == 1)
        #expect(session.csvExport.accounts.map(\.username) == ["f1", "f2", "f3"])
        session.setUnfollowed(true, username: "f1")
        #expect(model.followers?.accounts.first { $0.username == "f1" }?.unfollowedManually == true)
        #expect(account("aa", in: model)?.unfollowedManually == false)
    }

    /// Spec: Follower mode with no follower list invites a reimport instead of an empty list.
    @Test func followerModeWithoutFollowersInvitesReimport() throws {
        let (session, model) = try makeSession()
        #expect(!session.isAwaitingFollowerImport)

        model.listMode = .followers

        #expect(session.isAwaitingFollowerImport)
    }

    @Test func followerModeWithFollowersShowsTheList() throws {
        let (session, model) = try makeSession(followers: [makeAccount("f1", decision: .remove)])

        model.listMode = .followers

        #expect(!session.isAwaitingFollowerImport)
    }

    @Test func followerCSVFileName() throws {
        let (session, model) = try makeSession(followers: [makeAccount("f1", decision: .remove)])
        model.listMode = .followers

        let url = try session.writeCSV()

        #expect(url.lastPathComponent == "InstaSwipe-follower-2027-01-15.csv")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.split(separator: "\n").first == "username,link,ti segue dal,decisione,fatto,lo segui")
    }

    @Test func counterSumsBothLists() throws {
        let (session, _) = try makeSession(
            accounts: [makeAccount("aa", decision: .remove, done: true)],
            followers: [makeAccount("f1", decision: .remove, done: true)]
        )

        #expect(session.counterText == "Oggi: 2 azioni segnate")
    }

    @Test func promptKeepsOriginMode() throws {
        let (session, model) = try makeSession(
            accounts: [makeAccount("aa", decision: .remove)],
            followers: [makeAccount("aa", decision: .remove)]
        )
        model.listMode = .followers
        _ = session.open(makeAccount("aa", decision: .remove))
        model.listMode = .following
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        #expect(session.promptTitle(for: "aa") == "Hai rimosso @aa dai follower?")
        session.confirmUnfollowed()

        #expect(model.followers?.accounts.first?.unfollowedManually == true)
        #expect(account("aa", in: model)?.unfollowedManually == false)
    }

    @Test func promptTitleForFollowing() throws {
        let (session, _) = try makeSession()
        _ = session.open(makeAccount("aa", decision: .remove))
        session.scenePhaseChanged(.background)
        session.scenePhaseChanged(.active)

        #expect(session.promptTitle(for: "aa") == "Hai tolto il follow a @aa?")
    }
}
