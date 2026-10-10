import Synchronization
import Foundation

public import UttrflowCore

/// Types text as key events, the one route into a hidden field that never borrows the clipboard.
public protocol KeystrokeTyping: Sendable {
    /// Types `text` into whatever has focus, posting no key if this call throws.
    func type(_ text: String) throws(TextInsertionError)

    /// Presses Delete `count` times, which is the only way this route takes typed characters back; throws before posting any when a call fails.
    func deleteBackwards(_ count: Int) throws(TextInsertionError)
}

/// Puts text in by typing it, for the fields Accessibility cannot write into.
public struct TypedTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .typed

    private let focus: any AccessibilityFocus
    private let typist: any KeystrokeTyping
    private let writeState = TypedWriteState()
    private let finishWaitStarted: @Sendable () -> Void
    private let confirmation: PasteConfirmation

    public init(focus: any AccessibilityFocus, typist: any KeystrokeTyping) {
        self.init(focus: focus, typist: typist, finishWaitStarted: {})
    }

    init(
        focus: any AccessibilityFocus, typist: any KeystrokeTyping,
        confirmation: PasteConfirmation? = nil,
        finishWaitStarted: @escaping @Sendable () -> Void = {}
    ) {
        self.focus = focus
        self.typist = typist
        self.confirmation = confirmation ?? PasteConfirmation(focus: focus)
        self.finishWaitStarted = finishWaitStarted
    }

    /// Anything but ourselves, a focused control or a modal editor; Electron apps expose no focused element and still take typing.
    public func canInsert() async -> Bool {
        guard !focus.isSelfFrontmost() else { return false }
        let focus = focus
        let kind = await AccessibilityThread.run(orElse: .unpublished) { focus.focusedElementKind() }
        return kind != .control && !Self.keysMayBeCommands(in: focus.focusedApplication())
    }

    /// Reads the caret back after typing, since a key event posted is not a character accepted. See `Docs/insertion.md`.
    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        try await insert(text, targeting: nil)
    }

    /// Types only while the captured application is still in front and the dictation still wants the words.
    public func insert(
        _ text: String, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionArrival {
        try await insert(text, targeting: Optional(destination))
    }

    private func insert(
        _ text: String, targeting destination: InsertionDestination?
    ) async throws(TextInsertionError) -> InsertionArrival {
        try refuseIfStale(destination)
        // Read before the first key, so text already behind the caret cannot pass for the typed words.
        let focus = focus
        let before = await AccessibilityThread.run(orElse: FieldTail.unreadable) {
            focus.tail(upTo: PasteConfirmation.readLength)
        }
        try await typeInChunks(text, targeting: destination)
        return InsertionArrival(await confirmation.waitFor(text, before: before))
    }

    /// The one check made immediately before key events are posted: self in front, destination moved, or cancelled.
    func refuseIfStale(_ destination: InsertionDestination?) throws(TextInsertionError) {
        try TextInsertion.requireLive()
        try refuseIfUnsafeTarget(destination)
    }

    /// Checks the destination and field without cancellation, for restoring text already deleted by this write.
    func refuseIfUnsafeTarget(_ destination: InsertionDestination?) throws(TextInsertionError) {
        try refuseIfNotTypable()
        try TextInsertion.requireTarget(destination, focus: focus)
    }
}

extension TypedTextInsertionEngine: CompletionWriting {
    public func canWrite() async -> Bool { await canInsert() }

    /// Waits for an in-flight replacement before the application terminates.
    public func finishWrites() async { await writeState.closeAndWait(onWaiting: finishWaitStarted) }

    /// Backspaces then types, which the target's undo sees as several edits. See `Docs/predict-accept.md`.
    public func write(_ text: String, replacing replaced: String) async throws(TextInsertionError) {
        try await write(text, replacing: replaced, confirmedPreceding: nil)
    }

    public func write(
        _ text: String, replacing replaced: String, confirmedPreceding: String?
    ) async throws(TextInsertionError) {
        guard let write = writeState.begin() else {
            throw .insertionRejected(description: "the application is terminating")
        }
        defer { writeState.end(write) }
        let focus = focus
        let current = await AccessibilityThread.run(orElse: nil) { focus.focusedApplication() }
        let target = current.flatMap { $0.isKnown ? $0 : nil }
        let count = replaced.count
        try refuseIfStale(target)
        if count > 0, target == nil { throw .insertionUnconfirmed }
        if count > 0 {
            // A blind backspace could eat a shell prompt, so what is there is checked when the field will say.
            let preceding: String?
            if let confirmedPreceding {
                preceding = confirmedPreceding
            } else {
                let focus = focus
                preceding = await AccessibilityThread.run(orElse: nil) { focus.precedingText(count) }
            }
            if let preceding, preceding != replaced {
                throw .insertionRejected(
                    description: "the text before the caret is not what would be replaced")
            }
            try refuseIfStale(target)
            try typist.deleteBackwards(count)
        }
        try await typeInChunks(
            text, targeting: target, restoring: count > 0 ? replaced : nil)
    }
}

/// Tracks typed writes across their suspension points so quit waits through deletion and typing.
private final class TypedWriteState: Sendable {
    private struct State {
        var active: Set<UUID> = []
        var waiters: [CheckedContinuation<Void, Never>] = []
        var isClosed = false
    }

    private let state = Mutex(State())

    func begin() -> UUID? {
        state.withLock { state in
            guard !state.isClosed else { return nil }
            let id = UUID()
            state.active.insert(id)
            return id
        }
    }

    func end(_ id: UUID) {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.active.remove(id)
            guard state.active.isEmpty else { return [] }
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        for continuation in waiting { continuation.resume() }
    }

    func closeAndWait(onWaiting: @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                state.isClosed = true
                guard !state.active.isEmpty else { return true }
                state.waiters.append(continuation)
                onWaiting()
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

extension TypedTextInsertionEngine {
    /// Re-checked at the write rather than trusted from `canInsert()`, whose answer can go stale by now.
    private func refuseIfNotTypable() throws(TextInsertionError) {
        guard !focus.isSelfFrontmost(), focus.focusedElementKind() != .control else {
            throw .noFocusedTextField
        }
        guard !Self.keysMayBeCommands(in: focus.focusedApplication()) else { throw .noFocusedTextField }
    }

    /// Whether the table marks the app as one whose mode may turn typed letters into commands. See `Docs/compatibility.md`.
    static func keysMayBeCommands(in application: InsertionDestination?) -> Bool {
        guard let application else { return false }
        return DestinationClassifier.keysMayBeCommands(
            in: AppContext(
                applicationName: application.applicationName, bundleIdentifier: application.bundleIdentifier))
    }

    /// Characters posted between checks, small enough that a stop lands within a few milliseconds of typing.
    static let chunkLength = 64

    /// Types `text` a chunk at a time, making the pre-write check again before every chunk after the first.
    private func typeInChunks(
        _ text: String, targeting destination: InsertionDestination?, restoring replaced: String? = nil
    ) async throws(TextInsertionError) {
        let total = text.count
        let focus = focus
        // Without a captured destination, the app in front at the first chunk is the one typing must stay in.
        let current = await AccessibilityThread.run(orElse: nil) { focus.focusedApplication() }
        let target = destination ?? current.flatMap { $0.isKnown ? $0 : nil }
        var typed = 0
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: Self.chunkLength, limitedBy: text.endIndex) ?? text.endIndex
            do {
                if typed > 0 {
                    await Task.yield()
                }
                try refuseIfStale(target)
                try typist.type(String(text[start..<end]))
            } catch {
                // Characters already posted cannot be taken back, so any later stop is a partial insertion.
                guard typed == 0 else { throw .insertionInterrupted(typed: typed, total: total) }
                if let replaced {
                    guard let destination,
                        destination.processIdentifier != nil || destination.bundleIdentifier != nil
                    else {
                        throw .insertionUnconfirmed
                    }
                    do {
                        try refuseIfUnsafeTarget(destination)
                        try typist.type(replaced)
                    } catch { throw .insertionUnconfirmed }
                    throw .insertionUnconfirmed
                }
                throw error
            }
            typed += text.distance(from: start, to: end)
            start = end
        }
    }
}
