import UttrflowCore

/// Writes an emoji said by name, such as "thumbs up emoji", where the destination takes emoji and the user switched them on.
struct SpokenEmojiPass: PieceCleaningPass {
    static let id: PassID = .spokenEmoji
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    private let destination: Destination

    init(destination: Destination = .plain) {
        self.destination = destination
    }

    func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard
                let found = SpokenCommands.emoji.first(where: {
                    $0.isEnabled(in: destination) && draft.spells($0.words, at: position, in: live)
                }),
                position == 0
                    || !MentionGuard.isMentioned(
                        at: position, spanning: found.words.count, in: live, of: draft,
                        reach: MentionGuard.phraseReach, kind: .standalone)
            else {
                position += 1
                continue
            }
            // The emoji keeps the marks around its name: the first word's opening ones, the last word's closing ones.
            let first = live[position]
            let last = live[position + found.words.count - 1]
            let written =
                WordShape(draft.words[first].text).prefix + found.text
                + WordShape(draft.words[last].text).suffix
            draft.replace(at: first, with: written, by: Self.id)
            for index in live[(position + 1)..<(position + found.words.count)] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange((position + 1)..<(position + found.words.count))
            position += 1
        }
        return draft
    }
}
