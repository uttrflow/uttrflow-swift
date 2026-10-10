import Foundation
import Synchronization
import Testing
import UttrflowAccount
import UttrflowCore

@testable import Uttrflow

@Suite("Refreshing the signed-in account picture")
@MainActor
struct AvatarRefreshTests {
    @Test("the same avatar path is fetched again after the account changes")
    func refreshesPictureForNewAccount() async throws {
        let first = profile(identifier: "account-a")
        let second = profile(identifier: "account-b")
        let profiles = MutableProfileCache(first)
        let authentication = AvatarAuthentication(profile: first, pictures: [Data("A".utf8), Data("B".utf8)])
        let account = OnboardingAccountLayer(authentication: authentication, profiles: profiles)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = AppDelegate(container: root, account: account)
        app.drawsWindows = false
        app.readAccount()
        defer { try? FileManager.default.removeItem(at: root) }

        await app.refreshPictureThenRedraw()
        #expect(app.accountPage(at: .now).identity?.picture == Data("A".utf8))

        profiles.replace(with: second)
        app.readAccount()
        #expect(app.accountPage(at: .now).identity?.picture == nil)
        await app.refreshPictureThenRedraw()

        #expect(app.accountPage(at: .now).identity?.picture == Data("B".utf8))
        #expect(await authentication.avatarPaths == ["/v1/me/avatar", "/v1/me/avatar"])
    }

    @Test("the previous picture is cleared when the new account has no picture")
    func clearsPictureForAccountWithoutAvatar() async throws {
        let first = profile(identifier: "account-a")
        let second = profile(identifier: "account-b", avatarPath: nil)
        let profiles = MutableProfileCache(first)
        let authentication = AvatarAuthentication(profile: first, pictures: [Data("A".utf8)])
        let account = OnboardingAccountLayer(authentication: authentication, profiles: profiles)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = AppDelegate(container: root, account: account)
        app.drawsWindows = false
        app.readAccount()
        defer { try? FileManager.default.removeItem(at: root) }

        await app.refreshPictureThenRedraw()
        #expect(app.accountPage(at: .now).identity?.picture == Data("A".utf8))

        profiles.replace(with: second)
        app.readAccount()
        #expect(app.accountPage(at: .now).identity?.picture == nil)
        await app.refreshPictureThenRedraw()

        #expect(app.accountPage(at: .now).identity?.picture == nil)
        #expect(await authentication.avatarPaths == ["/v1/me/avatar"])
    }

    @Test("a late picture response cannot replace the newer account's picture")
    func ignoresLatePictureFromPreviousAccount() async throws {
        let first = profile(identifier: "account-a")
        let second = profile(identifier: "account-b")
        let profiles = MutableProfileCache(first)
        let authentication = AvatarAuthentication(
            profile: first, pictures: [Data("A".utf8), Data("B".utf8)], holdsFirstPicture: true)
        let account = OnboardingAccountLayer(authentication: authentication, profiles: profiles)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let app = AppDelegate(container: root, account: account)
        app.drawsWindows = false
        app.readAccount()
        defer { try? FileManager.default.removeItem(at: root) }

        let firstRefresh = Task { await app.refreshPictureThenRedraw() }
        await authentication.waitForAvatarRequests(1)
        profiles.replace(with: second)
        app.readAccount()
        await app.refreshPictureThenRedraw()
        await authentication.releaseFirstPicture()
        await firstRefresh.value

        #expect(app.accountPage(at: .now).identity?.picture == Data("B".utf8))
        #expect(await authentication.avatarPaths == ["/v1/me/avatar", "/v1/me/avatar"])
    }

    private func profile(identifier: String, avatarPath: String? = "/v1/me/avatar") -> Profile {
        let account = Account(
            identifier: identifier, displayName: identifier, emailAddress: nil,
            provider: .google, avatarPath: avatarPath)
        let entitlement = Entitlement(
            account: account, plan: .pro, expiresAt: .distantFuture, signature: "fixture")
        let subscription = Profile.Subscription(
            plan: .pro, status: .active, currentPeriodEnd: nil, effectivePlan: .pro,
            limits: Profile.Limits(monthlyMinutes: nil, customDictionaryEntries: nil))
        return Profile(
            account: account, subscription: subscription, devices: [], entitlement: entitlement,
            fetchedAt: Date(timeIntervalSince1970: 1))
    }
}

private final class MutableProfileCache: ProfileCache, Sendable {
    private let stored: Mutex<Profile?>

    init(_ profile: Profile) { stored = Mutex(profile) }

    func load() -> Profile? { stored.withLock { $0 } }
    func save(_ profile: Profile) throws(AccountError) { stored.withLock { $0 = profile } }
    func clear() { stored.withLock { $0 = nil } }
    func replace(with profile: Profile) { stored.withLock { $0 = profile } }
}

private actor AvatarAuthentication: AuthenticationService {
    private let profile: Profile
    private let pictures: [Data?]
    private let holdsFirstPicture: Bool
    private var nextPicture = 0
    private(set) var avatarPaths: [String] = []
    private var firstPicture: CheckedContinuation<Data?, Never>?
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated var signsInAsStandIn: Bool { false }

    init(profile: Profile, pictures: [Data?], holdsFirstPicture: Bool = false) {
        self.profile = profile
        self.pictures = pictures
        self.holdsFirstPicture = holdsFirstPicture
    }

    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        SignInChallenge(authorisationURL: URL(fileURLWithPath: "/unused"), state: "unused")
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile { profile }

    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        .noCredential
    }

    func avatar(at path: String) async -> Data? {
        let index = nextPicture
        nextPicture += 1
        avatarPaths.append(path)
        resumeRequestWaiters()
        guard pictures.indices.contains(index) else { return nil }
        if index == 0, holdsFirstPicture {
            return await withCheckedContinuation { firstPicture = $0 }
        }
        return pictures[index]
    }

    func signOut() async {}

    func deleteAccount() async throws(AccountError) {}

    func waitForAvatarRequests(_ count: Int) async {
        guard avatarPaths.count < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }

    func releaseFirstPicture() {
        firstPicture?.resume(returning: pictures.first ?? nil)
        firstPicture = nil
    }

    private func resumeRequestWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in requestWaiters {
            if avatarPaths.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
    }
}
