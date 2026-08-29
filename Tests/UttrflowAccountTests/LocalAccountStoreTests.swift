import Foundation
import Testing

@testable import UttrflowAccount

@Suite("Working on this Mac without an account")
struct LocalAccountStoreTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

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

    /// A name that is only spaces is not a name, and every page that draws this already
    /// knows how to say nothing. Normalising once here is what keeps each of them from
    /// having to know it too.
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

    /// The same rule ``ProfileCache`` keeps: a value that cannot be read means there is
    /// no local account, and the app opens on the page it would have opened on anyway.
    @Test("bytes that are not a local account read as no local account")
    func rubbishIsNotAnAccount() {
        let storage = MemoryStorage()
        storage.set(Data("not json".utf8), forKey: UserDefaultsLocalAccountStore.defaultKey)
        #expect(UserDefaultsLocalAccountStore(storage: storage).load() == nil)
    }

    /// The in-memory store ships in the module rather than in the tests, so it is worth
    /// one test of its own: a fake that quietly stopped behaving like the protocol would
    /// take every test built on it with it.
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
