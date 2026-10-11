// The one published legal document the app links to, carried as data so no view hard-codes it.
public import Foundation
internal import UttrflowAccount

/// A published document a person can open in the browser.
public struct PublishedLegalLink: Sendable, Equatable {
    /// The words of the link, which VoiceOver announces as a link.
    public let title: String
    /// The page it opens.
    public let destination: URL

    /// The Privacy page on the site; no Terms page is published, so none is linked.
    public static let privacy = PublishedLegalLink(
        title: "Privacy Policy", destination: PublishedPrivacyPage.address)
}
