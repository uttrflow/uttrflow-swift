public import Foundation

/// What can go wrong reading or writing a directory of measurements, read at a terminal, never by a user.
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

/// A directory holding one JSON file per record, written the moment each is finished.
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
        encoder.outputFormatting = .readable
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

    /// Every record in file-system order; a file that will not decode is raised, since writes are atomic.
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

extension JSONEncoder.OutputFormatting {
    /// Pretty, key-sorted and slash-friendly, so two files over the same data are byte-identical.
    static let readable: Self = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
}
