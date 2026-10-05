// Checks sealed headers and seals legacy plaintext pictures.

import Foundation
import UttrflowCore

/// Reads only the envelope prefix of already sealed pictures while migrating legacy files.
struct LegacyPictureMigration: Sendable {
    typealias Seal = @Sendable (Data, String) async -> Void
    typealias HeaderReader = @Sendable (URL) -> Data?
    typealias ContentsReader = @Sendable (URL) -> Data?

    private let readHeader: HeaderReader
    private let readContents: ContentsReader

    init(
        readHeader: @escaping HeaderReader = Self.header,
        readContents: @escaping ContentsReader = Self.contents
    ) {
        self.readHeader = readHeader
        self.readContents = readContents
    }

    func run(in folder: URL, seal: @escaping Seal) async {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        else { return }

        for url in files where url.pathExtension.lowercased() == "png" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                let header = readHeader(url)
            else { continue }
            if EncryptedStore.isSealed(header) { continue }
            guard let data = readContents(url) else { continue }
            await seal(data, url.lastPathComponent)
        }
    }

    private static func header(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: EncryptedStore.sealedHeaderLength)
    }

    private static func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
