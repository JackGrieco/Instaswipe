import SwiftUI

enum TutorialContext {
    /// No state yet: the tutorial is the app's first screen.
    case onboarding
    /// Opened from Impostazioni to make a new export.
    case settings
}

/// The four-phase guide from the Instagram app to the first swipe. Reaching phase 3 marks
/// the export as started, so the next launch resumes on the import (step 12).
struct ExportTutorialView: View {
    @Bindable var model: AppModel
    let context: TutorialContext
    @State private var phase: TutorialPhase

    init(model: AppModel, context: TutorialContext) {
        self.model = model
        self.context = context
        _phase = State(initialValue: ExportTutorial.startPhase(hasStartedExport: model.hasStartedExport))
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
            statusBarBackdrop
        }
        .background { background }
        .onChange(of: phase, initial: true) { _, current in
            if current == .waitForEmail { model.markExportStarted() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                if context == .onboarding && phase == .openExport { brand.padding(.bottom, 32) }
                TutorialPhaseView(phase: phase).id(phase)
                phaseFooter.padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .riseIn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    /// Covers the status bar, so scrolled text never sits under the clock. The reader stays
    /// inside the safe area: that is where `safeAreaInsets.top` reports the status bar height.
    private var statusBarBackdrop: some View {
        GeometryReader { proxy in
            Theme.bg
                .frame(height: proxy.safeAreaInsets.top)
                .offset(y: -proxy.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var brand: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Theme.pink.opacity(0.35), radius: 16, y: 14)
                .accessibilityHidden(true)
            Wordmark(size: 30)
        }
    }

    @ViewBuilder private var phaseFooter: some View {
        switch phase {
        case .waitForEmail:
            Text("L'email può arrivare anche dopo qualche ora. Puoi chiudere l'app: quando torni, ripartiamo dal passo 12.")
                .font(.outfit(15))
                .lineSpacing(4)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .importFile:
            VStack(spacing: 16) {
                if !model.isCloudAvailable { CloudOffWarning() }
                Button("Rivedi il tutorial dall'inizio") {
                    model.restartTutorial()
                    go(to: .openExport)
                }
                .font(.outfit(15, .medium))
                .foregroundStyle(Theme.pink)
                .accessibilityIdentifier("tutorialRestartButton")
            }
        case .openExport, .chooseData:
            EmptyView()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            if phase == .importFile {
                ImportControls(model: model)
            } else if let next = phase.next {
                Button(phase == .waitForEmail ? "È arrivata l'email" : "Avanti") { go(to: next) }
                    .buttonStyle(GradientButtonStyle(height: 58))
                    .accessibilityIdentifier("tutorialNextButton")
            }
            if let previous = phase.previous {
                Button("Indietro") { go(to: previous) }
                    .font(.outfit(15, .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(height: 36)
                    .accessibilityIdentifier("tutorialBackButton")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    private func go(to target: TutorialPhase) {
        withAnimation(.easeOut(duration: 0.25)) { phase = target }
    }

    /// Pink/purple glow behind the content.
    private var background: some View {
        ZStack(alignment: .top) {
            Theme.bg
            Circle()
                .fill(RadialGradient(
                    stops: [
                        .init(color: Theme.pink.opacity(0.22), location: 0),
                        .init(color: Theme.purple.opacity(0.10), location: 0.45),
                        .init(color: .clear, location: 0.7)
                    ],
                    center: .center, startRadius: 0, endRadius: 260
                ))
                .frame(width: 520, height: 520)
                .offset(y: -160)
        }
        .ignoresSafeArea()
    }
}
