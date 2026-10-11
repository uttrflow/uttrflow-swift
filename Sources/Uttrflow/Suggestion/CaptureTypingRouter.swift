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

    func finishEvents(
        _ reading: FieldReading, typed: Batch, at moment: Date,
        because reason: SuggestionReason, handed prior: (line: String, reading: FieldReading)?
    ) -> [CaptureEvent] {
        var events = typed.keys.map { CaptureEvent.typed($0, at: moment) }
        if typed.overflowed || typed.inserted {
            events.append(.inserted(at: moment))
        } else if !typed.keys.isEmpty, typed.keys.allSatisfy({ $0 != nil }),
            let prior, prior.reading == reading
        {
            let completed = typed.keys.reduce(prior.line) { $0 + ($1 ?? "") }
            events.append(.keystroke(completed, at: moment))
        }
        if case .applicationChanged = reason {
            events.append(.applicationDeactivated(at: moment))
        } else {
            events.append(.focusLeft(at: moment))
        }
        return events
    }
}
