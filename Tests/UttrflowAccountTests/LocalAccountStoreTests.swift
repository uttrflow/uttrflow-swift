import Foundation
import Testing

@testable import UttrflowAccount

/// ``UserDefaultsLocalAccountStore``, and the name normalisation ``LocalAccount`` does.
@Suite("Working on this Mac without an account")
struct LocalAccountStoreTests {
    /// The fixed instant the account is dated from.
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    /// A store over fresh in-memory bytes.
    private func store() -> UserDefaultsLocalAccountStore {
        UserDefaultsLocalAccountStore(storage: MemoryStorage())
    }

    @Test("what the store keeps, it reads back and can then forget")
    func roundTrip() {
        let store = store()
        #expect(store.load() == nil)

        store.save(LocalAccount(name: "Naveen Bhatt", since: noon))
        #expect(store.load() == LocalAccount(name: "Naveen Bhatt", since: noon))

        store.clear()
        #expect(store.load() == nil)
    }

    /// A blank name is normalised to none once here, so no page drawing it has to know.
    @Test(
        "a blank name is no name at all",
        arguments: ["", "   ", "\n"])
    func blankNamesAreAbsent(name: String) {
        #expect(LocalAccount(name: name, since: noon).name == nil)
        #expect(LocalAccount(name: nil, since: noon).name == nil)
    }

    @Test("keeps the name macOS gave it, without the whitespace around it")
    func namesAreTrimmed() {
        #expect(LocalAccount(name: "  Naveen  ", since: noon).name == "Naveen")
    }

    /// Unreadable bytes mean no local account, the same rule ``ProfileCache`` keeps.
    @Test("bytes that are not a local account read as no local account")
    func rubbishIsNotAnAccount() {
        let storage = MemoryStorage()
        storage.set(Data("not json".utf8), forKey: UserDefaultsLocalAccountStore.defaultKey)
        #expect(UserDefaultsLocalAccountStore(storage: storage).load() == nil)
    }

    /// The in-memory store ships in the module, so a fake drifting from the protocol is caught here.
    @Test("the in-memory store behaves as the real one does")
    func inMemoryAgrees() {
        let store = InMemoryLocalAccountStore()
        #expect(store.load() == nil)
        store.save(LocalAccount(name: "Naveen", since: noon))
        #expect(store.load()?.name == "Naveen")
        store.clear()
        #expect(store.load() == nil)
        #expect(InMemoryLocalAccountStore(LocalAccount(name: "A", since: noon)).load() != nil)
    }
}
