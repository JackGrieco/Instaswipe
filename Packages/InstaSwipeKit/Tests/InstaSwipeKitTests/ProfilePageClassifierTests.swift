import Foundation
import Testing
@testable import InstaSwipeKit

private let image = URL(string: "https://cdn.example.com/p.jpg")!

private func snapshot(
    path: String = "/luca_diddi/",
    ogTitle: String? = nil,
    ogImage: URL? = nil,
    body: String = ""
) -> ProfilePageSnapshot {
    ProfilePageSnapshot(
        finalURL: URL(string: "https://www.instagram.com\(path)")!,
        title: "Instagram",
        ogTitle: ogTitle,
        ogImage: ogImage,
        bodyText: body
    )
}

@Test func loginRedirectIsLoginRequired() {
    let result = ProfilePageClassifier.classify(
        snapshot(path: "/accounts/login/?next=/luca_diddi/", ogTitle: "Luca (@luca_diddi)"),
        username: "luca_diddi"
    )
    #expect(result == .loginRequired)
}

@Test func challengePathIsRateLimited() {
    let result = ProfilePageClassifier.classify(snapshot(path: "/challenge/abc/"), username: "luca_diddi")
    #expect(result == .rateLimited)
}

@Test func suspendedPathIsRateLimited() {
    let result = ProfilePageClassifier.classify(snapshot(path: "/accounts/suspended/"), username: "luca_diddi")
    #expect(result == .rateLimited)
}

@Test(arguments: [
    "Please wait a few minutes before you try again",
    "Attendi qualche minuto prima di riprovare",
    "try again later",
    "Riprova più tardi"
])
func rateLimitPhraseIsRateLimited(phrase: String) {
    let result = ProfilePageClassifier.classify(snapshot(body: "Oops. \(phrase). Thanks"), username: "luca_diddi")
    #expect(result == .rateLimited)
}

@Test func rateLimitBeatsProfileMetadata() {
    let result = ProfilePageClassifier.classify(
        snapshot(ogTitle: "Luca (@luca_diddi)", body: "Try Again Later"),
        username: "luca_diddi"
    )
    #expect(result == .rateLimited)
}

@Test func ogTitleWithUsernameIsProfile() {
    let result = ProfilePageClassifier.classify(
        snapshot(ogTitle: "Luca (@LUCA_DIDDI) on Instagram", ogImage: image),
        username: "luca_diddi"
    )
    #expect(result == .profile(displayName: "Luca", imageURL: image))
}

@Test func parsesNameFromItalianOgTitle() {
    let result = ProfilePageClassifier.classify(
        snapshot(ogTitle: "Luca Diddi (@luca_diddi) • Foto e video di Instagram", ogImage: image),
        username: "luca_diddi"
    )
    #expect(result == .profile(displayName: "Luca Diddi", imageURL: image))
}

@Test func nameEqualToUsernameBecomesNil() {
    let result = ProfilePageClassifier.classify(
        snapshot(ogTitle: "Luca_Diddi (@luca_diddi) • Instagram"),
        username: "luca_diddi"
    )
    #expect(result == .profile(displayName: nil, imageURL: nil))
}

@Test func emptyNameBecomesNil() {
    let result = ProfilePageClassifier.classify(snapshot(ogTitle: "(@luca_diddi)"), username: "luca_diddi")
    #expect(result == .profile(displayName: nil, imageURL: nil))
}

@Test func separatorOnlyNameBecomesNil() {
    let result = ProfilePageClassifier.classify(snapshot(ogTitle: " • (@luca_diddi)"), username: "luca_diddi")
    #expect(result == .profile(displayName: nil, imageURL: nil))
}

@Test(arguments: ["Sorry, this page isn't available", "Questa pagina non è disponibile"])
func missingPagePhraseWithoutOgTitleIsUnavailable(phrase: String) {
    let result = ProfilePageClassifier.classify(snapshot(body: phrase), username: "luca_diddi")
    #expect(result == .unavailable)
}

@Test func unavailableNeedsMissingOgTitle() {
    let result = ProfilePageClassifier.classify(
        snapshot(ogTitle: "Luca (@luca_diddi)", body: "Sorry, this page isn't available"),
        username: "luca_diddi"
    )
    #expect(result == .profile(displayName: "Luca", imageURL: nil))
}

@Test func emptyPageIsUnrecognizedNotUnavailable() {
    #expect(ProfilePageClassifier.classify(snapshot(), username: "luca_diddi") == .unrecognized)
}

@Test func ogTitleForOtherUserWithoutPhraseIsUnrecognized() {
    let result = ProfilePageClassifier.classify(snapshot(ogTitle: "Instagram"), username: "luca_diddi")
    #expect(result == .unrecognized)
}
