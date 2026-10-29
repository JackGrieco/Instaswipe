import InstaSwipeKit
import SwiftUI

struct MergeSummaryView: View {
    let model: AppModel
    let preview: MergePreview

    private var summary: MergeSummary { preview.summary }

    var body: some View {
        VStack(spacing: 0) {
            navRow
            hero.padding(.top, 28)
            if summary.isSuspicious { suspiciousWarning.padding(.top, 28) }
            rows.padding(.top, summary.isSuspicious ? 14 : 28)
            Spacer(minLength: 24)
            Button("Inizia a swipare") { model.confirmImport() }
                .buttonStyle(GradientButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .errorAlert(model)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(Theme.bg)
    }

    private var navRow: some View {
        ZStack {
            Text("Riepilogo import")
                .font(.outfit(17, .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Annulla") { model.cancelImport() }
                    .font(.outfit(16, .medium))
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button("Applica") { model.confirmImport() }
                    .font(.outfit(16, .bold))
                    .foregroundStyle(Theme.pink)
            }
        }
        .frame(height: 40)
    }

    private var hero: some View {
        VStack(spacing: 4) {
            Text(SwipeSession.groupedNumber(preview.state.accounts.count))
                .font(.outfit(64, .extraBold))
                .tracking(-0.04, size: 64)
                .monospacedDigit()
                .foregroundStyle(Theme.brandGradient)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Account totali dopo l'import")
                .font(.outfit(15))
                .foregroundStyle(Theme.ink2)
        }
        .accessibilityElement(children: .combine)
    }

    private var suspiciousWarning: some View {
        Text("Sembra un export incompleto: controlla di aver scelto l'intervallo «Sempre»")
            .font(.outfit(15, .semibold))
            .foregroundStyle(Theme.warningText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warningFill.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var rows: some View {
        VStack(spacing: 0) {
            row("Nuovi account", summary.newAccounts, showsSeparator: false)
            row("Non più seguiti", summary.noLongerFollowed)
            row("Segnati come già tolti", summary.autoMarkedDone)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .themeShadow()
    }

    private func row(_ title: String, _ value: Int, showsSeparator: Bool = true) -> some View {
        HStack {
            Text(title).font(.outfit(16)).foregroundStyle(Theme.ink)
            Spacer()
            Text(SwipeSession.groupedNumber(value))
                .font(.outfit(16, .semibold))
                .monospacedDigit()
                .foregroundStyle(value == 0 ? Theme.ink2 : Theme.ink)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .overlay(alignment: .top) {
            if showsSeparator { Rectangle().fill(Theme.line).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}
