import InstaSwipeKit
import SwiftUI

/// "Oggi: N unfollow segnati" with a meter up to the daily warning, orange once past it.
struct ReportCounterCard: View {
    let session: ReportSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.counterText)
                    .font(.outfit(17, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(session.isOverDailyWarning ? Theme.warningText : Theme.ink)
                    .accessibilityIdentifier("todayCounter")
                Spacer()
                Text("max \(Limits.dailyUnfollowWarning)")
                    .font(.outfit(12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
            }
            ProgressBar(
                fraction: Double(session.unfollowsToday) / Double(Limits.dailyUnfollowWarning),
                fill: session.isOverDailyWarning ? AnyShapeStyle(Theme.warningFill) : AnyShapeStyle(Theme.brandGradient)
            )
            if session.isOverDailyWarning {
                Text("Hai superato i \(Limits.dailyUnfollowWarning) di oggi: meglio fermarsi per evitare blocchi da Instagram.")
                    .font(.outfit(13))
                    .foregroundStyle(Theme.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surface))
        .themeShadow()
    }
}

/// Custom segmented control. Five filters don't fit "Da fare (1.638)" on one line, so the count sits under the title.
struct ReportFilterPicker: View {
    @Bindable var session: ReportSession

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ReportFilter.allCases, id: \.self) { filter in
                segment(filter)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
    }

    private func segment(_ filter: ReportFilter) -> some View {
        let isSelected = session.filter == filter
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { session.filter = filter }
        } label: {
            VStack(spacing: 0) {
                Text(ReportSession.title(for: filter))
                    .font(.outfit(13, isSelected ? .semibold : .medium))
                Text(SwipeSession.groupedNumber(session.count(for: filter)))
                    .font(.outfit(11, .medium))
                    .monospacedDigit()
                    .opacity(0.8)
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Theme.surface)
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(session.label(for: filter))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct ReportSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink2)
            TextField("", text: $text, prompt: Text("Cerca per nome o username").foregroundStyle(Theme.ink2))
                .font(.outfit(15))
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancella ricerca")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface2))
    }
}
