import Foundation

/// One instruction of the export tutorial, with the screenshot that shows it.
struct TutorialStep: Identifiable, Equatable {
    let number: Int
    let text: String
    /// Asset catalog name; nil when the step has no screenshot (the last one).
    let imageName: String?

    var id: Int { number }
}

/// The four screens of the tutorial, each covering a range of steps.
enum TutorialPhase: Int, CaseIterable, Identifiable {
    case openExport = 1
    case chooseData
    case waitForEmail
    case importFile

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .openExport: "Apri l'esportazione"
        case .chooseData: "Scegli cosa esportare"
        case .waitForEmail: "Aspetta l'email"
        case .importFile: "Importa"
        }
    }

    var steps: [TutorialStep] {
        ExportTutorial.steps.filter { stepRange.contains($0.number) }
    }

    var next: TutorialPhase? { TutorialPhase(rawValue: rawValue + 1) }
    var previous: TutorialPhase? { TutorialPhase(rawValue: rawValue - 1) }

    private var stepRange: ClosedRange<Int> {
        switch self {
        case .openExport: 1...6
        case .chooseData: 7...10
        case .waitForEmail: 11...11
        case .importFile: 12...14
        }
    }
}

enum ExportTutorial {
    private static let texts = [
        "Apri Instagram, vai sul tuo profilo e tocca le tre righe ☰ in alto a destra",
        "Tocca «Account Meta»",
        "Tocca «Le tue informazioni e autorizzazioni»",
        "Tocca «Esporta le tue informazioni»",
        "Tocca «Crea esportazione» e scegli il tuo profilo Instagram",
        "Scegli «Esporta sul dispositivo»",
        "In «Personalizza informazioni» deseleziona tutto tranne «Follower e persone/Pagine seguite»",
        "In «Intervallo di date» scegli «Sempre»",
        "In «Formato» scegli «JSON»",
        "In «Qualità dei contenuti multimediali» scegli «Qualità inferiore»",
        "Tocca «Avvia esportazione» e aspetta l'email di conferma di Meta",
        "Quando arriva l'email, scarica il file ZIP e aprilo (estrailo) dall'app File",
        "Torna in InstaSwipe, scegli la cartella estratta e tocca «Apri»",
        "Comincia a swipare!"
    ]

    static let steps: [TutorialStep] = texts.enumerated().map { index, text in
        let number = index + 1
        let imageName = number < texts.count ? String(format: "TutorialStep%02d", number) : nil
        return TutorialStep(number: number, text: text, imageName: imageName)
    }

    /// After the export was started (phase 3 reached) the user comes back for the import.
    static func startPhase(hasStartedExport: Bool) -> TutorialPhase {
        hasStartedExport ? .importFile : .openExport
    }
}
