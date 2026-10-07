// Fetches a model's assets at install time, the module's only network call.
internal import Foundation
internal import Synchronization
internal import UttrflowCore
private import CryptoKit

// The one file in UttrflowSpeech allowed to open a connection; Scripts/offline_audit.sh names it.

/// Fetches every file in a model's folder at install time, pinned to a commit and checked file by file.
func downloadWeights(
    for model: SpeechModel, into destination: URL,
    onProgress: @escaping @Sendable (Double) -> Void
) async throws {
    let total = max(model.weightFiles.values.reduce(Int64(0)) { $0 + $1.bytes }, 1)
    var completed = try completedPinnedWeightBytes(for: model, in: destination)
    onProgress(Double(completed) / Double(total))

    guard !model.weightFiles.isEmpty else {
        throw SpeechModelFetchFailure(reason: "\(model.variant) has no recorded files")
    }
    for (name, expected) in model.weightFiles.sorted(by: { $0.key < $1.key }) {
        let file = destination.appending(path: name)
        if try verified(file: file, expected: expected) {
            continue
        }

        let completedBeforeFile = completed
        try await fetchPinnedFile(
            repository: model.weightsRepository,
            revision: model.weightsRevision,
            path: "\(model.variant)/\(name)",
            destination: file,
            expected: expected
        ) { bytes in
            onProgress(Double(completedBeforeFile + bytes) / Double(total))
        }
        completed += expected.bytes
        onProgress(Double(completed) / Double(total))
    }
}

/// Fetches a model's tokenizer at install time, so WhisperKit never reaches for one while decoding.
func downloadTokenizer(for model: SpeechModel, into destination: URL) async throws {
    for name in TokenizerAssets.fileNames {
        guard
            let url = URL(
                string:
                    "https://huggingface.co/\(model.tokenizerRepository)/resolve/\(model.tokenizerRevision)/\(name)"
            )
        else {
            throw TokenizerFetchFailure(reason: "\(model.tokenizerRepository) is not an address")
        }

        // No token and no endpoint of anybody's choosing: this fetches a public file and says who nobody is.
        NetworkActivityLedger.shared.record(.modelDownload)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TokenizerFetchFailure(
                reason: "\(model.tokenizerRepository) answered \(status) for \(name)")
        }

        // A pinned commit says which file to fetch; only the digest says it is the file that was pinned.
        guard let expected = model.tokenizerDigests[name] else {
            throw TokenizerFetchFailure(reason: "\(name) has no recorded digest to check against")
        }
        let found = hexDigest(SHA256.hash(data: data))
        guard found == expected else {
            throw TokenizerFetchFailure(
                reason: "\(name) from \(model.tokenizerRepository) hashed \(found), not \(expected)")
        }

        // Atomic, so a dropped connection cannot leave a truncated file that passes as a tokenizer.
        try PrivateFile.write(data, to: destination.appending(path: name))
    }
}

private func completedPinnedWeightBytes(for model: SpeechModel, in destination: URL) throws -> Int64 {
    var completed: Int64 = 0
    for (name, expected) in model.weightFiles {
        if try verified(file: destination.appending(path: name), expected: expected) {
            completed += expected.bytes
        }
    }
    return completed
}

func verified(file: URL, expected: SpeechModelFile) throws -> Bool {
    guard onDiskSize(of: file) == expected.bytes else { return false }
    return try sha256(of: file) == expected.sha256
}

/// The file's size as the disk has it now, or nil when it is missing; URL resource values are cached per URL and go stale while a download writes.
func onDiskSize(of file: URL) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
}

typealias SpeechAssetDownloader =
    @Sendable (
        URLRequest, URL, Int64, @escaping @Sendable (Int64) -> Void
    ) async throws -> URLResponse

func fetchPinnedFile(
    repository: String,
    revision: String,
    path: String,
    destination: URL,
    expected: SpeechModelFile,
    downloader: SpeechAssetDownloader? = nil,
    onProgress: @escaping @Sendable (Int64) -> Void
) async throws {
    guard let url = URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(path)") else {
        throw SpeechModelFetchFailure(reason: "\(repository) is not an address")
    }

    let fileManager = FileManager.default
    let parent = destination.deletingLastPathComponent()
    try PrivateFile.makeDirectory(at: parent)
    let partial = parent.appending(path: ".\(destination.lastPathComponent).partial")
    let fetch = downloader ?? downloadSpeechAsset
    var offset = try partialSize(partial, expected: expected)
    if fileManager.fileExists(atPath: partial.path) { try PrivateFile.tighten(at: partial) }

    for attempt in 0...1 {
        if offset == expected.bytes, try verified(file: partial, expected: expected) {
            break
        }
        let response = try await fetch(
            speechAssetRequest(from: url, startingAt: offset), partial, offset, onProgress)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else {
            if offset > 0, attempt == 0 {
                try? fileManager.removeItem(at: partial)
                offset = 0
                continue
            }
            throw SpeechModelFetchFailure(reason: "\(repository) answered \(status) for \(path)")
        }

        if try verified(file: partial, expected: expected) { break }
        if attempt == 0, offset > 0 {
            try? fileManager.removeItem(at: partial)
            offset = 0
            continue
        }
        let received = onDiskSize(of: partial) ?? -1
        let found = (try? sha256(of: partial)) ?? "unavailable"
        try? fileManager.removeItem(at: partial)
        throw SpeechModelFetchFailure(
            reason:
                "\(path) was \(received) bytes with SHA-256 \(found), expected \(expected.bytes) bytes and \(expected.sha256)"
        )
    }

    guard try verified(file: partial, expected: expected) else {
        throw SpeechModelFetchFailure(reason: "\(path) could not be verified after download")
    }
    try PrivateFile.tighten(at: partial)

    if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: partial, to: destination)
    try PrivateFile.tighten(at: destination)
    onProgress(expected.bytes)
}

private func partialSize(_ file: URL, expected: SpeechModelFile) throws -> Int64 {
    let size = onDiskSize(of: file) ?? 0
    guard size > 0, size <= expected.bytes else { return 0 }
    return size
}

func speechAssetRequest(from url: URL, startingAt offset: Int64) -> URLRequest {
    var request = URLRequest(url: url)
    if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
    return request
}

func openSpeechAssetOutput(at partial: URL, statusCode: Int, requestedOffset: Int64) throws -> FileHandle {
    if statusCode == 206, requestedOffset > 0 {
        let output = try FileHandle(forWritingTo: partial)
        try output.seekToEnd()
        return output
    }
    _ = FileManager.default.createFile(atPath: partial.path, contents: nil)
    try PrivateFile.tighten(at: partial)
    let output = try FileHandle(forWritingTo: partial)
    try output.truncate(atOffset: 0)
    return output
}

private func downloadSpeechAsset(
    _ request: URLRequest, to partial: URL, startingAt offset: Int64,
    onProgress: @escaping @Sendable (Int64) -> Void
) async throws -> URLResponse {
    NetworkActivityLedger.shared.record(.modelDownload)
    let download = SpeechAssetURLSessionDownload(
        partial: partial, requestedOffset: offset, onProgress: onProgress)
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            download.start(request, continuation: continuation)
        }
    } onCancel: {
        download.cancel()
    }
}

private final class SpeechAssetURLSessionDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct SessionState: Sendable {
        var session: URLSession?
        var task: URLSessionTask?
        var cancelled = false
    }

    private let onProgress: @Sendable (Int64) -> Void
    private let partial: URL
    private let requestedOffset: Int64
    private let state = Mutex(SessionState())
    private var continuation: CheckedContinuation<URLResponse, any Error>?
    private var output: FileHandle?
    private var response: URLResponse?
    private var received: Int64 = 0
    private var writeError: (any Error)?

    init(partial: URL, requestedOffset: Int64, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.partial = partial
        self.requestedOffset = requestedOffset
        self.onProgress = onProgress
    }

    func start(
        _ request: URLRequest, continuation: CheckedContinuation<URLResponse, any Error>
    ) {
        self.continuation = continuation
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        state.withLock { state in
            state.session = session
            state.task = task
            task.resume()
            if state.cancelled {
                task.cancel()
            }
        }
    }

    func cancel() {
        state.withLock { state in
            state.cancelled = true
            state.task?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            completionHandler(.allow)
            return
        }
        do {
            output = try openSpeechAssetOutput(
                at: partial, statusCode: http.statusCode, requestedOffset: requestedOffset)
            completionHandler(.allow)
        } catch {
            writeError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try output?.write(contentsOf: data)
            received += Int64(data.count)
            onProgress(
                (response as? HTTPURLResponse)?.statusCode == 206 ? requestedOffset + received : received)
        } catch {
            writeError = error
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        defer {
            session.finishTasksAndInvalidate()
            state.withLock {
                $0.session = nil
                $0.task = nil
            }
        }
        try? output?.close()
        output = nil
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let writeError {
            continuation.resume(throwing: writeError)
        } else if let response {
            continuation.resume(returning: response)
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}

private func sha256(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hexDigest(hasher.finalize())
}

private func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}

/// Why a tokenizer could not be fetched; a sentence for the log, since nothing branches on it.
struct TokenizerFetchFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

/// Why a speech model asset could not be fetched; a sentence for the log.
struct SpeechModelFetchFailure: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}
