import Foundation
import UttrflowPredictCapture

@MainActor
final class CaptureTypingRouter {
    struct Batch {
        let keys: [String?]
        let overflowed: Bool
        let inserted: Bool

        init(keys: [String?], overflowed: Bool, inserted: Bool = false) {
            self.keys = keys
            self.overflowed = overflowed
            self.inserted = inserted
        }
    }

    static let maximumKeys = 256
    static let maximumCharacters = 4_096

    private(set) var keys: [String?] = []
    private(set) var overflowed = false
    private var characterCount = 0
    private var endTask: Task<Void, Never>?

    func append(_ key: String?) {
        guard !overflowed else { return }
        let addedCharacters = key?.utf16.count ?? 0
        guard keys.count < Self.maximumKeys,
            characterCount <= Self.maximumCharacters - addedCharacters
        else {
            discard()
            overflowed = true
            return
        }
        keys.append(key)
        characterCount += addedCharacters
    }

    func drain(markingInsertion inserted: Bool = false) -> Batch {
        defer { discard() }
        return Batch(keys: keys, overflowed: overflowed, inserted: inserted)
    }

    @discardableResult
    func discard() -> Bool {
        let discardedTyping = !keys.isEmpty || overflowed
        keys.removeAll(keepingCapacity: false)
        characterCount = 0
        overflowed = false
        return discardedTyping
    }

    func finishPreviousField(
        _ reading: FieldReading, using capture: CaptureSession, typed: Batch, at moment: Date,
        because reason: SuggestionReason, handed prior: (line: String, reading: FieldReading)?
    ) {
        let precedingEnd = endTask
        endTask = Task { [weak self] in
            await precedingEnd?.value
            guard let self else { return }
            await finish(
                reading, using: capture, typed: typed, at: moment, because: reason, handed: prior)
        }
    }

    func waitForPreviousField() async {
        await endTask?.value
    }

    func finish(
        _ reading: FieldReading, using capture: CaptureSession, typed: Batch, at moment: Date,
        because reason: SuggestionReason, handed prior: (line: String, reading: FieldReading)?
    ) async {
        for key in typed.keys { _ = try? await capture.handle(.typed(key, at: moment), in: reading) }
        if typed.overflowed || typed.inserted {
            _ = try? await capture.handle(.inserted(at: moment), in: reading)
        } else if !typed.keys.isEmpty, typed.keys.allSatisfy({ $0 != nil }),
            let prior, prior.reading == reading
        {
            let completed = typed.keys.reduce(prior.line) { $0 + ($1 ?? "") }
            _ = try? await capture.handle(.keystroke(completed, at: moment), in: reading)
        }
        let ending: CaptureEvent
        if case .applicationChanged = reason {
            ending = .applicationDeactivated(at: moment)
        } else {
            ending = .focusLeft(at: moment)
        }
        _ = try? await capture.handle(ending, in: reading)
    }
}
