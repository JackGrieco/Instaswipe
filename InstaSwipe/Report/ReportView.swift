import InstaSwipeKit
import SwiftUI

/// A plain `List` styled as the "Aura" cards, so rows keep their native swipe actions.
struct ReportView: View {
    private static let listCornerRadius: CGFloat = 22

    @Bindable var model: AppModel
    @State private var session: ReportSession
    @State private var toast: Toast?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    private let thumbnails = ThumbnailCache()

    init(model: AppModel) {
        self.model = model
        _session = State(initialValue: ReportSession(model: model))
    }

    var body: some View {
        List {
            Group {
                header
                // The picker stays in the invite too, so the user can switch back.
                ListModePicker(mode: $model.listMode)
                if session.isAwaitingFollowerImport {
                    NoFollowersView().padding(.vertical, 36)
                } else {
                    ReportCounterCard(session: session)
                    ReportFilterPicker(session: session)
                    ReportSearchField(text: $session.searchText)
                }
            }
            .reportListRow(insets: EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            if !session.isAwaitingFollowerImport { rowsList }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.top, 10, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .background(Theme.bg.ignoresSafeArea())
        .toast($toast)
        .onChange(of: scenePhase) { _, phase in session.scenePhaseChanged(phase) }
        .sheet(isPresented: promptBinding) { promptSheet }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Da togliere")
                .font(.outfit(32, .bold))
                .tracking(-0.02, size: 32)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // Nothing to export before the follower list exists.
            if !session.isAwaitingFollowerImport { shareButton }
            SettingsButton()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var shareButton: some View {
        let export = session.csvExport
        return ShareLink(item: export, preview: SharePreview(export.fileName)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.surface2))
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .accessibilityLabel("Condividi CSV")
    }

    @ViewBuilder private var rowsList: some View {
        let rows = session.rows
        if rows.isEmpty {
            Text("Nessun account qui")
                .font(.outfit(15))
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(RoundedRectangle(cornerRadius: Self.listCornerRadius, style: .continuous).fill(Theme.surface))
                .reportListRow(insets: EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
        } else {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, account in
                ReportRow(account: account, thumbnails: thumbnails, showsSeparator: index > 0, mode: model.listMode) {
                    Haptics.impact(.soft)
                    session.setUnfollowed(!account.unfollowedManually, username: account.username)
                }
                .background(rowBackground(isFirst: index == 0, isLast: index == rows.count - 1))
                .onTapGesture { openURL(session.open(account)) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipeActions(for: account) }
                .reportListRow(insets: EdgeInsets(top: index == 0 ? 7 : 0, leading: 16, bottom: 0, trailing: 16))
            }
        }
    }

    /// Each row draws its slice of the rounded list card.
    private func rowBackground(isFirst: Bool, isLast: Bool) -> some View {
        let top: CGFloat = isFirst ? Self.listCornerRadius : 0
        let bottom: CGFloat = isLast ? Self.listCornerRadius : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom,
            topTrailingRadius: top, style: .continuous
        )
        .fill(Theme.surface)
    }

    @ViewBuilder private func swipeActions(for account: FollowedAccount) -> some View {
        Button("Tengo") { session.decide(.keep, username: account.username) }.tint(Theme.green)
        Button("Tolgo") { session.decide(.remove, username: account.username) }.tint(Theme.red)
        Button("Da decidere") { session.decide(.pending, username: account.username) }.tint(.gray)
        if session.filter == .gone || account.availability == .unavailable {
            Button("Riprova") { session.retryAvailability(username: account.username) }.tint(.blue)
        }
    }

    private var promptBinding: Binding<Bool> {
        Binding(get: { session.promptUsername != nil }, set: { if !$0 { session.dismissPrompt() } })
    }

    @ViewBuilder private var promptSheet: some View {
        if let username = session.promptUsername {
            ReturnPromptSheet(
                account: model.list(session.returnPrompt.prompt?.mode ?? model.listMode)?.accounts.first { $0.username == username },
                username: username,
                title: session.promptTitle(for: username),
                thumbnails: thumbnails,
                onConfirm: {
                    session.confirmUnfollowed()
                    toast = .markedDone
                },
                onNotYet: session.dismissPrompt,
                onKeep: {
                    session.changeMindKeep()
                    toast = .keptAfterAll
                }
            )
        }
    }
}

private extension View {
    func reportListRow(insets: EdgeInsets) -> some View {
        listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
