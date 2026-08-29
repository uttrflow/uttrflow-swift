import UttrflowCore

/// Re-reading the truth, and doing the one thing that can follow from it.
///
/// Called on launch and whenever the app has reason to think something may have changed.
/// It is deliberately tiny and deliberately not part of ``AuthenticationService``: the
/// service knows how to ask the server, and this knows what the answer means for the copy
/// on this disk. Keeping them apart is what lets the meaning be tested without a network
/// and the asking be tested without a cache.
///
/// The one rule worth stating: **a failure changes nothing.** A Mac that cannot reach the
/// server keeps the profile it has, because being offline is not a reason to stop working.
/// Only the server saying "I do not know this session" clears anything — and that is not a
/// failure, it is somebody on another machine having signed this one out.
///
/// A Mac that holds no credential to ask with is covered by the same rule, and it is worth
/// spelling out because it looks like a sign-out and is not one. The refresh token lives in
/// the Keychain and the profile does not, precisely so that the profile survives the
/// Keychain losing its entry — a signing identity that changed, or an ad-hoc build rebuilt
/// since the last sign-in, both of which ``KeychainTokenStore`` describes. Deleting the
/// profile because the credential beside it went missing would undo that decision and hand
/// the user the exact failure it was made to prevent: a sign-in that completes, and a
/// second launch that says "Not signed in".
public struct AccountRefresh: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// The server confirmed the cached copy. Nothing was written.
        case unchanged
        /// A newer copy was cached in place of the old one.
        case updated
        /// The session is over; the cached profile has been removed.
        case signedOut
        /// The server could not be reached or could not be believed. Nothing changed.
        case unavailable
        /// There is no credential on this Mac to renew with, so nothing was asked and
        /// nothing was written. The cached profile — if there is one — is still there,
        /// and keeps working until it expires on its own.
        case noCredential
    }

    private let service: any AuthenticationService
    private let profiles: any ProfileCache

    public init(service: any AuthenticationService, profiles: any ProfileCache) {
        self.service = service
        self.profiles = profiles
    }

    /// - Returns: What happened, for a caller that wants to redraw. Never throws: nothing
    ///   here is a failure a user could act on, and a launch that reported one would be
    ///   an error dialog for a network hiccup.
    @discardableResult
    public func run() async -> Outcome {
        let cached = profiles.load()
        do throws(AccountError) {
            switch try await service.currentProfile(ifChangedFrom: cached) {
            case .unchanged:
                return .unchanged
            case .updated(let profile):
                // A profile that fails the signature check is dropped, not cached and not
                // acted on. The one already on disk was believed once and keeps working,
                // which is the safer of the two wrong answers.
                do throws(AccountError) {
                    try profiles.save(profile)
                    return .updated
                } catch {
                    return .unavailable
                }
            case .signedOut:
                // Local data is untouched. Signing out is losing an account, never losing
                // your words — see ``ProfileCache/clear()``.
                profiles.clear()
                return .signedOut
            case .noCredential:
                // Deliberately not ``profiles/clear()``. Nobody said this session is over:
                // this Mac simply has nothing to ask with, which is a statement about the
                // Keychain and not about the account.
                return .noCredential
            }
        } catch {
            return .unavailable
        }
    }
}
