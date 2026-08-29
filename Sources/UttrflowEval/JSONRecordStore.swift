public import Foundation

/// What can go wrong reading or writing a directory of measurements.
///
/// Deliberately not a ``UttrflowFailure``: that protocol exists so the app can put a
/// sentence in front of a user, and nobody using the product will ever see one of
/// these. They are read by whoever is running the harness, at a terminal, with the
/// directory in front of them.
public enum EvaluationStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case couldNotWrite(path: String, reason: String)
    case couldNotRead(path: String, reason: String)

    public var description: String {
        switch self {
        case .couldNotWrite(let path, let reason): "could not write \(path): \(reason)"
        case .couldNotRead(let path, let reason): "could not read \(path): \(reason)"
        }
    }
}

/// A directory holding one JSON file per record, named by its id.
///
/// The shape `uttrflow-bakeoff` established: each result is written the moment it is
/// finished, so a run that dies half way through has still banked everything before the
/// point it died, and `--summarise` can print what exists without measuring anything
/// again. Here it earns its keep twice over — the recording session is a person reading
/// out loud for twenty minutes, and asking them to start again because the nineteenth
/// passage crashed would be unforgivable.
public struct JSONRecordStore<Record: Codable & Sendable & Identifiable>: Sendable
where Record.ID == String {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Where a sibling file for the same record lives — the audio next to its metadata.
    public func url(for id: String, extension pathExtension: String) -> URL {
        directory.appending(path: "\(id).\(pathExtension)")
    }

    public func contains(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id, extension: "json").path)
    }

    public func save(_ record: Record) throws(EvaluationStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw .couldNotWrite(path: "\(record.id).json", reason: "\(error)")
        }
        try write(data, to: url(for: record.id, extension: "json"))
    }

    /// Writes a sibling file — the recording itself, or the passage as plain text.
    public func write(
        _ data: Data, for id: String, extension pathExtension: String
    ) throws(EvaluationStoreError) {
        try write(data, to: url(for: id, extension: pathExtension))
    }

    /// Every record in the directory, in whatever order the file system offers.
    ///
    /// A file that will not decode is raised rather than skipped. Records are written
    /// atomically, so a broken one is not a half-finished write — it is something that
    /// has been edited or truncated, and quietly ignoring it would present a partial
    /// corpus as a complete one.
    public func all() throws(EvaluationStoreError) -> [Record] {
        // Nothing recorded yet is not an error; it is the first run.
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        } catch {
            throw .couldNotRead(path: directory.path, reason: "\(error)")
        }

        var records: [Record] = []
        for file in files where file.pathExtension == "json" {
            do {
                records.append(try JSONDecoder().decode(Record.self, from: Data(contentsOf: file)))
            } catch {
                throw .couldNotRead(path: file.lastPathComponent, reason: "\(error)")
            }
        }
        return records
    }

    private func write(_ data: Data, to url: URL) throws(EvaluationStoreError) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite(path: url.lastPathComponent, reason: "\(error)")
        }
    }
}
