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
    /// Account whose profile was just opened in Instagram; the prompt waits for the app to come back.
    private(set) var returnPromptUsername: String?
    /// Account the "did you unfollow?" sheet is about; non-nil while the sheet is shown.
    private(set) var promptUsername: String?

    @ObservationIgnored private var hasLeftApp = false
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

    var rows: [FollowedAccount] {
        model.state.map { Report.accounts(filter, search: searchText, in: $0) } ?? []
    }

    func label(for filter: ReportFilter) -> String {
        let count = model.state.map { Report.counts(in: $0)[filter] ?? 0 } ?? 0
        return "\(Self.title(for: filter)) (\(count))"
    }

    private static func title(for filter: ReportFilter) -> String {
        switch filter {
        case .toDo: "Da fare"
        case .done: "Fatti"
        case .gone: "Spariti"
        case .kept: "Tenuti"
        }
    }

    var unfollowsToday: Int {
        model.state.map { Report.unfollowsToday(in: $0, now: now(), calendar: calendar) } ?? 0
    }

    var counterText: String { "Oggi: \(unfollowsToday) unfollow segnati" }

    var isOverDailyWarning: Bool { unfollowsToday >= Limits.dailyUnfollowWarning }

    // MARK: Actions

    func setUnfollowed(_ done: Bool, username: String) {
        model.apply { Report.setUnfollowed(done, username: username, in: $0, now: now()) }
    }

    func decide(_ decision: Decision, username: String) {
        model.apply { Review.decide(decision, username: username, in: $0, now: now()) }
    }

    func retryAvailability(username: String) {
        model.apply { Review.markAvailability(.unknown, displayName: nil, username: username, in: $0) }
    }

    // MARK: Return from Instagram

    /// Returns the URL to open. Only accounts marked "Tolgo" get the return prompt.
    func open(_ account: FollowedAccount) -> URL {
        returnPromptUsername = account.decision == .remove ? account.username : nil
        hasLeftApp = false
        return account.profileURL
    }

    /// The `.active` that fires right after the tap is ignored: the prompt needs a real round trip.
    func scenePhaseChanged(_ phase: ScenePhase) {
        guard returnPromptUsername != nil else { return }
        switch phase {
        case .inactive, .background:
            hasLeftApp = true
        case .active:
            guard hasLeftApp else { return }
            promptUsername = returnPromptUsername
            returnPromptUsername = nil
            hasLeftApp = false
        @unknown default:
            break
        }
    }

    func confirmUnfollowed() {
        if let username = promptUsername { setUnfollowed(true, username: username) }
        dismissPrompt()
    }

    func changeMindKeep() {
        if let username = promptUsername { decide(.keep, username: username) }
        dismissPrompt()
    }

    func dismissPrompt() {
        promptUsername = nil
    }

    // MARK: CSV

    /// Snapshot handed to the share sheet; the file is only written when the user actually shares.
    var csvExport: CSVExport {
        CSVExport(accounts: model.state?.accounts ?? [], now: now(), timeZone: calendar.timeZone, directory: directory)
    }

    func writeCSV() throws -> URL { try csvExport.writeFile() }
}

struct CSVExport: Transferable, Sendable {
    let accounts: [FollowedAccount]
    let now: Date
    let timeZone: TimeZone
    let directory: URL

    var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "InstaSwipe-\(formatter.string(from: now)).csv"
    }

    func writeFile() throws -> URL {
        let url = directory.appendingPathComponent(fileName)
        try CSVExporter.csv(for: accounts).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            SentTransferredFile(try export.writeFile())
        }
    }
}
