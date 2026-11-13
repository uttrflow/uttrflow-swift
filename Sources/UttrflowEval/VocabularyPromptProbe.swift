// The vocabulary prompt measured under each language hint on Hindi speech: which form keeps the decoder in Devanagari and hears the names.
package import UttrflowCore

/// One invented Hindi sentence holding invented names, in both scripts.
package struct VocabularyPromptItem: Sendable, Equatable {
    package let id: String
    /// What `say` reads and the reference the transcript is scored against.
    package let sentence: String
    /// The names as the sentence writes them.
    package let names: [String]
    /// The same names as a person types them into the dictionary.
    package let romanisedNames: [String]
}

/// What the recogniser is conditioned on before it decodes a clip.
package enum VocabularyPromptCondition: String, CaseIterable, Sendable {
    /// No prompt at all.
    case none
    /// Today's frame around the dictionary's Latin spellings.
    case latinFrame
    /// The same frame around the names written in Devanagari.
    case devanagariFrame
    /// The Devanagari names alone, handed over as the text before the caret, which carries no frame.
    case wordsOnly

    /// The vocabulary and the text before the caret this condition hands the recogniser for `item`.
    package func prompt(for item: VocabularyPromptItem) -> (vocabulary: [String], precedingText: String?) {
        switch self {
        case .none: ([], nil)
        case .latinFrame: (item.romanisedNames, nil)
        case .devanagariFrame: (item.names, nil)
        case .wordsOnly: ([], item.names.joined(separator: " "))
        }
    }
}

/// One clip decoded under one hint and one condition, scored for script, names and words.
package struct VocabularyPromptRow: Sendable, Equatable {
    package let item: VocabularyPromptItem
    /// The language hint, or "auto" for none.
    package let hint: String
    package let condition: VocabularyPromptCondition
    package let transcript: String

    package init(
        item: VocabularyPromptItem, hint: String, condition: VocabularyPromptCondition, transcript: String
    ) {
        self.item = item
        self.hint = hint
        self.condition = condition
        self.transcript = transcript
    }

    /// The share of the transcript's letters written in Devanagari, or 0 when it holds none.
    package var devanagariShare: Double {
        let letters = transcript.unicodeScalars.filter(\.properties.isAlphabetic)
        guard !letters.isEmpty else { return 0 }
        return Double(letters.count { Self.devanagari.contains($0.value) }) / Double(letters.count)
    }

    /// Whether the Hindi speech came back out of Devanagari, romanised or in English: under a fifth of its letters are Devanagari.
    package var leftDevanagari: Bool { devanagariShare < 0.2 }

    /// How many of the item's names the transcript holds, in either script.
    package var namesHeard: Int {
        let words = Set(TailCommit.scoredWords(transcript))
        return zip(item.names, item.romanisedNames).count { devanagari, latin in
            words.contains(TailCommit.normalized(devanagari)) || words.contains(TailCommit.normalized(latin))
        }
    }

    /// The word errors against the Devanagari sentence.
    package var wordErrors: WordErrorRate {
        TailCommit.wordErrorRate(hypothesis: transcript, reference: item.sentence)
    }

    private static let devanagari: ClosedRange<UInt32> = 0x0900...0x097F
}

/// The rows summed per hint and condition, as the table `Docs/vocabulary-prompt-hindi.md` records.
package struct VocabularyPromptTable: Sendable {
    package let rows: [VocabularyPromptRow]

    package init(rows: [VocabularyPromptRow]) { self.rows = rows }

    /// One line per hint and condition: clips, clips that left Devanagari, Devanagari share, names heard and word error rate.
    package var markdown: String {
        var lines = [
            "| Hint | Prompt | Clips | Left Devanagari | Devanagari share | Names heard | Word error rate |",
            "|---|---|---|---|---|---|---|",
        ]
        for hint in Array(Set(rows.map(\.hint))).sorted() {
            for condition in VocabularyPromptCondition.allCases {
                let group = rows.filter { $0.hint == hint && $0.condition == condition }
                guard !group.isEmpty else { continue }
                let names = group.reduce(0) { $0 + $1.item.names.count }
                let heard = group.reduce(0) { $0 + $1.namesHeard }
                let errors = group.reduce(0) { $0 + $1.wordErrors.errors }
                let words = group.reduce(0) { $0 + $1.wordErrors.referenceWordCount }
                let share = group.reduce(0) { $0 + $1.devanagariShare } / Double(group.count)
                let cells = [
                    hint, condition.rawValue, "\(group.count)", "\(group.count { $0.leftDevanagari })",
                    Self.percent(share), "\(heard)/\(names)",
                    Self.percent(Double(errors) / Double(max(words, 1))),
                ]
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}

/// Invented Hindi and code-mixed sentences, each holding names no recogniser was trained on.
package enum VocabularyPromptCorpus {
    package static let items: [VocabularyPromptItem] = [
        item("hi-01", "कल वरीकेश से मिलना है", ["वरीकेश"], ["Varikesh"]),
        item("hi-02", "तोलांशी ने खाना बना दिया", ["तोलांशी"], ["Tolanshi"]),
        item("hi-03", "यह किताब किरवान को दे दो", ["किरवान"], ["Kirvaan"]),
        item("hi-04", "शुभ्रत और दर्वीका कल आएंगे", ["शुभ्रत", "दर्वीका"], ["Shubhrat", "Darvika"]),
        item("hi-05", "मेहांश भाई से बात हुई", ["मेहांश"], ["Mehaansh"]),
        item("hi-06", "हम नीलोर गाँव चलेंगे", ["नीलोर"], ["Nilor"]),
        item("hi-07", "सायंक जी अभी घर पर नहीं हैं", ["सायंक"], ["Saayank"]),
        item("hi-08", "मैंने ओरवीना को चिट्ठी लिखी", ["ओरवीना"], ["Orvina"]),
        item("mix-01", "कल की मीटिंग में वरीकेश रिपोर्ट दिखाएगा", ["वरीकेश"], ["Varikesh"]),
        item("mix-02", "तोलांशी को ईमेल भेज दो", ["तोलांशी"], ["Tolanshi"]),
        item("mix-03", "किरवान का फोन नंबर अपडेट करना है", ["किरवान"], ["Kirvaan"]),
        item("mix-04", "शुभ्रत ने प्रोजेक्ट की फाइल शेयर की", ["शुभ्रत"], ["Shubhrat"]),
    ]

    private static func item(
        _ id: String, _ sentence: String, _ names: [String], _ romanised: [String]
    ) -> VocabularyPromptItem {
        VocabularyPromptItem(id: id, sentence: sentence, names: names, romanisedNames: romanised)
    }
}
