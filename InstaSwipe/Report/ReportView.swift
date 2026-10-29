import InstaSwipeKit
import SwiftUI

struct ReportView: View {
    let model: AppModel
    @State private var session: ReportSession
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let thumbnails = ThumbnailCache()

    init(model: AppModel) {
        self.model = model
        _session = State(initialValue: ReportSession(model: model))
    }

    var body: some View {
        List {
            Section { counter }
            Section { picker }
            Section { rowsList }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $session.searchText, prompt: "Cerca per nome o username")
        .toolbar { shareButton }
        .onChange(of: scenePhase) { _, phase in session.scenePhaseChanged(phase) }
        .sheet(isPresented: promptBinding) { promptSheet }
    }

    private var counter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.counterText)
                .font(.headline)
                .foregroundStyle(session.isOverDailyWarning ? Color.orange : Color.primary)
                .accessibilityIdentifier("todayCounter")
            if session.isOverDailyWarning {
                Text("Hai superato i \(Limits.dailyUnfollowWarning) di oggi: meglio fermarsi per evitare blocchi da Instagram.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var picker: some View {
        Picker("Filtro", selection: $session.filter) {
            ForEach(ReportFilter.allCases, id: \.self) { filter in
                Text(session.label(for: filter)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var rowsList: some View {
        ForEach(session.rows) { account in
            ReportRow(account: account, thumbnails: thumbnails) {
                session.setUnfollowed(!account.unfollowedManually, username: account.username)
            }
            .onTapGesture { openURL(session.open(account)) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeActions(for: account) }
        }
    }

    @ViewBuilder private func swipeActions(for account: FollowedAccount) -> some View {
        Button("Tengo") { session.decide(.keep, username: account.username) }.tint(.green)
        Button("Tolgo") { session.decide(.remove, username: account.username) }.tint(.red)
        Button("Da decidere") { session.decide(.pending, username: account.username) }.tint(.gray)
        if session.filter == .gone || account.availability == .unavailable {
            Button("Riprova") { session.retryAvailability(username: account.username) }.tint(.blue)
        }
    }

    @ToolbarContentBuilder private var shareButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ShareLink(item: session.csvExport, preview: SharePreview("InstaSwipe.csv")) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Condividi CSV")
        }
    }

    private var promptBinding: Binding<Bool> {
        Binding(get: { session.promptUsername != nil }, set: { if !$0 { session.dismissPrompt() } })
    }

    @ViewBuilder private var promptSheet: some View {
        if let username = session.promptUsername {
            ReturnPromptSheet(
                username: username,
                onConfirm: session.confirmUnfollowed,
                onNotYet: session.dismissPrompt,
                onKeep: session.changeMindKeep
            )
        }
    }
}
