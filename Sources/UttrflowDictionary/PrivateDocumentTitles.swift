// Window titles that name a sensitive kind of document, which the dictionary never learns from.

/// The shipped document categories whose titles are never mined; keyed by category, never by a person's file name.
enum PrivateDocumentTitles {
    /// A kind of document a person would not expect a dictionary to read.
    enum Category: String, CaseIterable {
        case medical, legal, financial, tax, identity, employment, immigration
    }

    /// Phrases per category, lowercase words matched whole and in order; data, so a category grows by a row.
    static let phrases: [Category: [[String]]] = [
        .medical: [
            ["medical"], ["diagnosis"], ["prescription"], ["patient"], ["lab", "results"],
            ["health", "record"],
            ["discharge", "summary"], ["therapy"], ["radiology"], ["pathology"],
        ],
        .legal: [
            ["lawsuit"], ["affidavit"], ["settlement"], ["divorce"], ["custody"], ["subpoena"],
            ["power", "of", "attorney"],
            ["non", "disclosure"], ["nda"], ["will", "and", "testament"],
        ],
        .financial: [
            ["bank", "statement"], ["credit", "report"], ["loan", "application"], ["mortgage"], ["payslip"],
            ["pay", "stub"],
            ["salary"], ["net", "worth"],
        ],
        .tax: [["tax", "return"], ["tax", "form"], ["w2"], ["w-2"], ["1099"], ["form", "16"], ["itr"]],
        .identity: [
            ["passport"], ["driver", "license"], ["driving", "licence"], ["social", "security"], ["aadhaar"],
            ["birth", "certificate"],
        ],
        .employment: [
            ["performance", "review"], ["resignation"], ["offer", "letter"], ["disciplinary"], ["severance"],
        ],
        .immigration: [["visa", "application"], ["immigration"], ["asylum"], ["green", "card"]],
    ]

    /// The category whose phrase the title contains, if any.
    static func category(of title: String) -> Category? {
        let words = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
        for category in Category.allCases {
            for phrase in phrases[category] ?? [] where contains(phrase, in: words) { return category }
        }
        return nil
    }

    private static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains {
            Array(words[$0..<($0 + phrase.count)]) == phrase
        }
    }
}
