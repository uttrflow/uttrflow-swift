// The file that keeps the speech model's last loads across launches, so an update's recompile has a record.

import Darwin
public import Foundation

/// The speech model's recent loads on disk, private to this user and never uploaded.
public struct SpeechModelLoadLog: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    /// Where this build keeps the log inside `directory`.
    public static func defaultFile(in directory: URL) -> URL {
        LocalStoreEntry.speechModelLoads.location(in: directory)
    }

    /// The kept loads; a missing or unreadable file is an empty history, and an unreadable one is set aside.
    public func history() -> SpeechModelLoadHistory {
        LocalStore.read(SpeechModelLoadHistory.self, from: file).value ?? SpeechModelLoadHistory()
    }

    /// Judges and keeps a finished load, answering the record it kept.
    @discardableResult
    public func record(
        seconds: Double, parts: SpeechModelLoadParts?, modelRevision: String,
        systemBuild: String = SpeechModelLoadLog.currentSystemBuild, at date: Date = Date()
    ) throws -> SpeechModelLoadRecord {
        let stored = LocalStore.read(SpeechModelLoadHistory.self, from: file)
        var history = stored.value ?? SpeechModelLoadHistory()
        let record = history.append(
            date: date, seconds: seconds, parts: parts, systemBuild: systemBuild,
            modelRevision: modelRevision)
        // A file that could not be moved aside is still under this name, and writing would destroy it.
        guard !stored.isLeftInPlace else { return record }
        try PrivateFile.write(JSONEncoder().encode(history), to: file)
        return record
    }

    /// This Mac's macOS build, such as "25F71", or "unknown" when the kernel does not say.
    public static var currentSystemBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var value = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
    }
}
