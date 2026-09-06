import UttrflowCore

/// Re-reads the profile and applies what the answer means to the cached copy; a failure changes nothing.
public struct AccountRefresh: Sendable {
    /// What the refresh did to the cached profile.
    public enum Outcome: Sendable, Equatable {
        /// The server confirmed the cached copy; nothing was written.
        case unchanged
        /// A newer copy was cached in place of the previous one.
        case updated
        /// The session is over; the cached profile has been removed.
        case signedOut
        /// The server could not be reached or could not be believed. Nothing changed.
        case unavailable
        /// Nothing to renew with, so nothing was asked; the cached profile stays until it expires on its own.
        case noCredential
    }

    /// Asks the server.
    private let service: any AuthenticationService
    /// The copy on this disk.
    private let profiles: any ProfileCache

    /// Pairs the service that asks with the cache that keeps the answer.
    public init(service: any AuthenticationService, profiles: any ProfileCache) {
        self.service = service
        self.profiles = profiles
    }

    /// Applies the answer to the cache and says what happened; never throws, as nothing here earns a dialog.
    @discardableResult
    public func run() async -> Outcome {
        let cached = profiles.load()
        do throws(AccountError) {
            switch try await service.currentProfile(ifChangedFrom: cached) {
            case .unchanged:
                return .unchanged
            case .updated(let profile):
                // A profile failing the signature check is dropped; the one on disk keeps working.
                do throws(AccountError) {
                    try profiles.save(profile)
                    return .updated
                } catch {
                    return .unavailable
                }
            case .signedOut:
                // Local data is untouched: signing out loses an account, never words.
                profiles.clear()
                return .signedOut
            case .noCredential:
                // Not a clear: nobody said the session is over; this Mac merely has nothing to ask with.
                return .noCredential
            }
        } catch {
            return .unavailable
        }
    }
}
