import Foundation
import InstaSwipeKit
import Observation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Drives the "Da togliere" list: filter, search, counters, the "did you unfollow?" prompt and CSV export.
@MainActor
@Observable
final class ReportSession {
    var filter = ReportFilter.toDo
    var searchText = ""
    let returnPrompt = ReturnPromptTracker()
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let directory: URL

    init(
        model: AppModel,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        directory: URL = FileManager.default.temporaryDirectory
    ) {
        self.model = model
        self.now = now
        self.calendar = calendar
        self.directory = directory
    }

    // MARK: State

    private var activeList: AccountList? { model.list(model.listMode) }

    /// Follower mode with no follower list: the view shows the reimport invite instead of the list.
    var isAwaitingFollowerImport: Bool { model.isAwaitingFollowerImport }

    var rows: [FollowedAccount] {
        activeList.map { Report.accounts(filter, search: searchText, in: $0) } ?? []
    }

    func count(for filter: ReportFilter) -> Int {
        activeList.map { Report.counts(in: $0)[filter] ?? 0 } ?? 0
    }

    func label(for filter: ReportFilter) -> String {
        "\(Self.title(for: filter)) (\(count(for: filter)))"
    }

    static func title(for filter: ReportFilter) -> String {
        switch filter {
        case .toDo: "Da fare"
        case .unsure: "Dubbi"
        case .done: "Fatti"
        case .gone: "Spariti"
        case .kept: "Tenuti"
        }
    }

    /// Unfollows plus follower removals marked today.
    var unfollowsToday: Int { model.actionsToday(now: now(), calendar: calendar) }

    var counterText: String { "Oggi: \(unfollowsToday) azioni segnate" }

    var isOverDailyWarning: Bool { unfollowsToday >= Limits.dailyUnfollowWarning }

    // MARK: Actions

    func setUnfollowed(_ done: Bool, username: String) {
        setUnfollowed(done, username: username, mode: model.listMode)
    }

    func decide(_ decision: Decision, username: String) {
        decide(decision, username: username, mode: model.listMode)
    }

    func retryAvailability(username: String) {
        model.applyToBothLists {
            Review.markAvailability(.unknown, displayName: nil, username: username, in: $0)
        }
    }

    private func setUnfollowed(_ done: Bool, username: String, mode: ListMode) {
        model.apply(mode) { Report.setUnfollowed(done, username: username, in: $0, now: now()) }
    }

    private func decide(_ decision: Decision, username: String, mode: ListMode) {
        model.apply(mode) { Review.decide(decision, username: username, in: $0, now: now()) }
    }

    // MARK: Return from Instagram

    /// Account whose profile was just opened in Instagram; the prompt waits for the app to come back.
    var returnPromptUsername: String? { returnPrompt.pending?.username }
    /// Account the "did you unfollow?" sheet is about; non-nil while the sheet is shown.
    var promptUsername: String? { returnPrompt.prompt?.username }

    /// Returns the URL to open. Only accounts marked "Tolgo" get the return prompt.
    func open(_ account: FollowedAccount) -> URL {
        returnPrompt.willOpen(account.decision == .remove ? .init(username: account.username, mode: model.listMode) : nil)
        return account.profileURL
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        returnPrompt.scenePhaseChanged(phase)
    }

    /// Acts on the list the profile was opened from, even if the mode changed meanwhile.
    func confirmUnfollowed() {
        if let prompt = returnPrompt.prompt { setUnfollowed(true, username: prompt.username, mode: prompt.mode) }
        dismissPrompt()
    }

    func changeMindKeep() {
        if let prompt = returnPrompt.prompt { decide(.keep, username: prompt.username, mode: prompt.mode) }
        dismissPrompt()
    }

    func promptTitle(for username: String) -> String {
        (returnPrompt.prompt?.mode ?? model.listMode).returnPromptTitle(for: username)
    }

    func dismissPrompt() {
        returnPrompt.dismiss()
    }

    // MARK: CSV

    /// Snapshot handed to the share sheet; the file is only written when the user actually shares.
    var csvExport: CSVExport {
        CSVExport(accounts: activeList?.accounts ?? [], mode: model.listMode, now: now(), timeZone: calendar.timeZone, directory: directory)
    }

    func writeCSV() throws -> URL { try csvExport.writeFile() }
}

struct CSVExport: Transferable, Sendable {
    let accounts: [FollowedAccount]
    let mode: ListMode
    let now: Date
    let timeZone: TimeZone
    let directory: URL

    var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(mode.csvFilePrefix)-\(formatter.string(from: now)).csv"
    }

    func writeFile() throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        try CSVExporter.csv(for: accounts, mode: mode).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try export.writeFile())
        }
    }
}
