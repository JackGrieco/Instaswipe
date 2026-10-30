import SwiftUI
import UIKit

/// One phase of the export tutorial: progress, title, the current step's screenshot
/// (always in view) and the phase's steps, kept in sync with the screenshot.
struct TutorialPhaseView: View {
    private static let screenshotHeightRatio: CGFloat = 0.46

    let phase: TutorialPhase
    /// Optional because it doubles as the carousel's scroll position.
    @State private var selectedStep: Int?

    init(phase: TutorialPhase) {
        self.phase = phase
        _selectedStep = State(initialValue: phase.steps.first?.number)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FASE \(phase.rawValue) DI \(TutorialPhase.allCases.count)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.ink2)
                .accessibilityIdentifier("tutorialPhaseKicker")
            progressBar.padding(.top, 10)
            Text(phase.title)
                .font(.outfit(26, .bold))
                .tracking(-0.01, size: 26)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20)
            carousel.padding(.top, 16)
            if phase.steps.count > 1 { dots.padding(.top, 10) }
            stepsList.padding(.top, 16)
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(TutorialPhase.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= phase.rawValue ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.surface2))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    /// A paging horizontal scroll view, not a page-style `TabView`: the latter swallows the
    /// vertical drags that should scroll the whole phase.
    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(phase.steps) { step in
                    screenshot(for: step)
                        .containerRelativeFrame(.horizontal)
                        .id(step.number)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selectedStep)
        .scrollIndicators(.hidden)
        .scrollDisabled(phase.steps.count < 2)
        .containerRelativeFrame(.vertical) { height, _ in height * Self.screenshotHeightRatio }
    }

    @ViewBuilder
    private func screenshot(for step: TutorialStep) -> some View {
        Group {
            if let name = step.imageName, UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line))
            } else if step.imageName == nil {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 116, height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Text(String(format: "%02d", step.number))
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.text)
    }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(phase.steps) { step in
                Capsule()
                    .fill(step.number == selectedStep ? Theme.pink : Theme.line)
                    .frame(width: step.number == selectedStep ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var stepsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(phase.steps.enumerated()), id: \.element.id) { index, step in
                stepRow(step)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stepRow(_ step: TutorialStep) -> some View {
        let isSelected = step.number == selectedStep
        return Button {
            withAnimation { selectedStep = step.number }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", step.number))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Theme.pink : Theme.ink2)
                Text(step.text)
                    .font(.outfit(14, isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Theme.pink.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
