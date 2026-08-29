import Foundation

@testable import UttrflowDictionary

/// A fixed instant. Nothing in this module reads the real clock, so a slow machine
/// cannot change a result and a test never has to sleep to get a predictable one.
let epoch = Date(timeIntervalSince1970: 1_700_000_000)

/// One entry, with only the fields a given test cares about spelt out.
func word(
    _ spelling: String,
    saying pronunciation: String? = nil,
    from origin: WordOrigin = .learned,
    used: Int = 0,
    reverted: Int = 0,
    daysAgo: Double = 0,
    id: UUID = UUID()
) -> DictionaryEntry {
    DictionaryEntry(
        id: id, word: spelling, pronunciation: pronunciation, origin: origin,
        firstSeen: epoch.addingTimeInterval(-daysAgo * 86_400),
        timesUsed: used, timesReverted: reverted)
}

/// A directory of its own per test, removed with the test. Real files, because the
/// store's whole job is what happens on disk and a substitute would test the substitute.
struct Sandbox: ~Copyable {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-dictionary-\(UUID().uuidString)")
    }

    /// The folder the store is expected to make for itself. Deliberately absent to
    /// begin with.
    var folder: URL { root.appending(path: "Uttrflow") }

    /// The path the store is pointed at.
    var file: URL { folder.appending(path: "dictionary.v1.json") }

    /// What is actually on disk, decoded — the only honest way to check that a write
    /// reached it.
    func onDisk() -> [DictionaryEntry]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([DictionaryEntry].self, from: data)
    }

    /// Puts bytes where the store will look, so a test can hand it a file it did not
    /// write: an old dictionary, or a mangled one.
    func seed(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file)
    }

    func seed(_ entries: [DictionaryEntry]) throws {
        try seed(JSONEncoder().encode(entries))
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}
