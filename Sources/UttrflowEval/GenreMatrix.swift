// The writing genres whole-dictation cases are drawn from, and how each genre scores as one text.

/// A kind of whole text a person dictates, where several formatting classes meet inside one piece.
public enum Genre: String, Sendable, Equatable, CaseIterable, Codable {
    case customerEmail = "customer-email"
    case chatReply = "chat-reply"
    case meetingMinutes = "meeting-minutes"
    case statusReport = "status-report"
    case proposal
    case apology
    case coverLetter = "cover-letter"
    case invitation
    case shoppingList = "shopping-list"
    case recipe
    case travelPlan = "travel-plan"
    case clinicNote = "clinic-note"
    case legalClause = "legal-clause"
    case essayParagraph = "essay-paragraph"
    case poem
    case productDescription = "product-description"
    case socialPost = "social-post"
    case announcement
    case correctedReply = "corrected-reply"
    case hinglishTechnical = "hinglish-technical"
}

/// How many cases each genre has, and how one engine's outputs score on them, genre by genre.
public struct GenreMatrix: Sendable, Equatable {
    /// The fewest cases a genre needs to count as covered.
    public static let coveredFloor = 3

    /// One genre's row: its case ids in corpus order, and the scores of the outputs given for them.
    public struct Row: Sendable, Equatable {
        public let genre: Genre
        public let caseIDs: [String]
        public let spokenWords: Int
        public let scores: [CaseScore]

        public var isCovered: Bool { caseIDs.count >= GenreMatrix.coveredFloor }
        public var exact: Int { scores.count(where: \.isExact) }
        public var passed: Int { scores.count(where: \.passed) }
        public var meanSimilarity: Double { mean(\.similarity) }
        public var meanMarkAccuracy: Double { mean(\.markAccuracy) }

        private func mean(_ metric: KeyPath<CaseScore, Double>) -> Double {
            guard !scores.isEmpty else { return 0 }
            return scores.map { $0[keyPath: metric] }.reduce(0, +) / Double(scores.count)
        }
    }

    public let rows: [Row]

    /// The matrix read from `cases`, with each case scored on `outputs[id]` where one is given.
    public init(cases: [EvaluationCase] = EvaluationCorpus.genres, outputs: [String: String] = [:]) {
        rows = Genre.allCases.map { genre in
            let members = cases.filter { $0.genre == genre }
            return Row(
                genre: genre, caseIDs: members.map(\.id),
                spokenWords: members.reduce(0) { $0 + Scorer.tokens($1.spoken).count },
                scores: members.compactMap { member in
                    outputs[member.id].map { Scorer.score($0, against: member) }
                })
        }
    }

    /// The matrix as the Markdown page `Docs/genre-matrix.md` holds, scored on the rules path.
    public var markdown: String {
        var lines = [
            "# Genre coverage matrix",
            "",
            "Generated from `EvaluationCorpus.genres` and what `RuleBasedTransformer` writes for each case; do not edit by hand.",
            "The genre cases are kept out of `EvaluationCorpus.all` until the meaning guard stops refusing their references.",
            "Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter GenreMatrixTests`.",
            "A genre is covered at \(Self.coveredFloor) cases. Exact is the whole text character for character;",
            "similarity is word agreement and marks is comma and sentence-end agreement, each a mean over the genre.",
            "",
            "| Genre | Cases | Spoken words | Rules exact | Rules passed | Similarity | Marks | Covered |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for row in rows {
            lines.append(
                "| \(row.genre.rawValue) | \(row.caseIDs.count) | \(row.spokenWords) "
                    + "| \(row.exact) of \(row.scores.count) | \(row.passed) of \(row.scores.count) "
                    + "| \(Self.percent(row.meanSimilarity)) | \(Self.percent(row.meanMarkAccuracy)) "
                    + "| \(row.isCovered ? "yes" : "no") |")
        }
        let zero = rows.filter { !$0.scores.isEmpty && $0.exact == 0 }.map { "`\($0.genre.rawValue)`" }
        let named = zero.isEmpty ? "none" : zero.joined(separator: ", ")
        lines += ["", "Genres at 0% exact on the rules path: \(named)."]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
