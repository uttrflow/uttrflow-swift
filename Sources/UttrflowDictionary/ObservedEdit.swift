// The one replaced word range between what was inserted and what the person left.

import UttrflowCore

/// One word range the person replaced in inserted text; see Docs/app-dictionary.md.
struct ObservedEdit: Sendable, Equatable {
    /// The words that were inserted and are gone, as inserted.
    let heard: [String]
    /// The words the person left in their place, as left.
    let wrote: [String]
    /// The index of the first heard word among the inserted text's words.
    let position: Int

    /// The one contiguous replacement between the texts; insertions, deletions, moves and rewrites yield `nil`.
    static func between(inserted: String, left: String) -> ObservedEdit? {
        let before = LearnableWords.words(in: inserted, atMost: .max)
        let after = LearnableWords.words(in: left, atMost: .max)
        let alignment = WordErrorRate.measure(
            reference: before.map { $0.lowercased() }, hypothesis: after.map { $0.lowercased() }
        ).alignment

        var run: (position: Int, heard: Range<Int>, wrote: Range<Int>)?
        var beforeIndex = 0
        var afterIndex = 0
        for operation in alignment {
            let isMatch = operation.kind == .match
            let takesBefore = operation.kind != .insertion
            let takesAfter = operation.kind != .deletion
            if !isMatch {
                if var open = run {
                    // A run ends at a match, so a second one apart from the first is a second edit.
                    guard open.heard.upperBound == beforeIndex, open.wrote.upperBound == afterIndex else {
                        return nil
                    }
                    open.heard = open.heard.lowerBound..<(beforeIndex + (takesBefore ? 1 : 0))
                    open.wrote = open.wrote.lowerBound..<(afterIndex + (takesAfter ? 1 : 0))
                    run = open
                } else {
                    run = (
                        beforeIndex,
                        beforeIndex..<(beforeIndex + (takesBefore ? 1 : 0)),
                        afterIndex..<(afterIndex + (takesAfter ? 1 : 0))
                    )
                }
            }
            beforeIndex += takesBefore ? 1 : 0
            afterIndex += takesAfter ? 1 : 0
        }

        let limit = LearnableWords.maximumWordsInACorrection
        guard let run, (1...limit).contains(run.heard.count), (1...limit).contains(run.wrote.count)
        else { return nil }
        return ObservedEdit(
            heard: Array(before[run.heard]), wrote: Array(after[run.wrote]), position: run.position)
    }
}
