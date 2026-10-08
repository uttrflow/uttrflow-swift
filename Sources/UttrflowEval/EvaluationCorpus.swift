// The hand-written clean-up cases every candidate is measured against.
public import UttrflowCore

/// The hand-written cases every clean-up candidate is measured against; each list is read from `Resources/Corpus/`.
public enum EvaluationCorpus {
    public static let all: [EvaluationCase] =
        everyday + technical + notARequest + hostileSelectedText + hostileWindowTitle + multilingual
        + contextual + codeToken + grammar + secondLanguage + oneLineField + bareLiteral + formatting
        + codeMixing + commandInput + segments + longInput

    public static func cases(in category: EvaluationCase.Category) -> [EvaluationCase] {
        all.filter { $0.category == category }
    }

    public static func cases(for language: LanguageCode) -> [EvaluationCase] {
        all.filter { $0.language == language }
    }

    // MARK: Everyday speech

    static let everyday: [EvaluationCase] = CorpusFile.cases(in: .everyday)

    // MARK: Technical terms that must survive

    static let technical: [EvaluationCase] = CorpusFile.cases(in: .technical)

    // MARK: Utterances that are not addressed to the model

    /// One case per request-shaped dictation, by class; see `requestCases`.
    static let notARequest: [EvaluationCase] = requestCases.map(\.evaluation)

    // MARK: Hostile instructions on screen, quoted as selected text rather than spoken. See Docs/ai-context-line.md.

    /// Pairs ordinary dictation with a hostile `selectedText`; withhold context for the control run.
    static let hostileSelectedText: [EvaluationCase] = CorpusFile.cases(
        in: .notARequest, set: "hostileSelectedText")

    // MARK: Hostile instructions on screen, carried by the window title. See Docs/ai-context-line.md.

    /// Pairs ordinary dictation with a hostile window title (`documentName`); nothing is selected.
    static let hostileWindowTitle: [EvaluationCase] = CorpusFile.cases(
        in: .notARequest, set: "hostileWindowTitle")

    // MARK: Hinglish, romanised the way people type it; none of these sentences is in the prompt

    static let multilingual: [EvaluationCase] = CorpusFile.cases(in: .multilingual)

    // MARK: Context pairs, identical words under two windows. See Docs/eval-context-cases.md.

    static let contextual: [EvaluationCase] = CorpusFile.cases(in: .contextual)

    // MARK: Letter-and-digit codes, whose capital no sentence start explains

    /// Each said into a notes document with the caret where the words land.
    static let codeToken: [EvaluationCase] = CorpusFile.cases(in: .technical, set: "codeToken")

    // MARK: Grammar slips and dialect

    /// Model cases: the rules never repair a slip, and `RulesCorpusTests` proves the floor leaves each of these alone.
    static let grammar: [EvaluationCase] = CorpusFile.cases(in: .grammar)

    // MARK: Second-language grammar

    /// Second-language article, preposition, tense and agreement errors, written down as spoken where no repair is the policy.
    static let secondLanguage: [EvaluationCase] = CorpusFile.cases(in: .secondLanguage)

    // MARK: A dictation that is only a literal

    static let bareLiteral: [EvaluationCase] = CorpusFile.cases(in: .bareLiteral)

    // MARK: One-line fields of no known purpose

    static let oneLineField: [EvaluationCase] = CorpusFile.cases(in: .oneLineField)

    // MARK: Launcher panels, whose one input is a query or a command

    /// Each reports a plain one-line text field, so the launcher's row, not the role, decides the policy.
    static let commandInput: [EvaluationCase] = CorpusFile.cases(in: .commandInput)

    // MARK: Long inputs

    /// Invented meeting notes past three hundred words, said with no marks.
    static let longInput: [EvaluationCase] = CorpusFile.cases(in: .longInput)

    // MARK: Abstention. See Docs/formatting-matrix.md.

    /// Invented prose full of notation words, each sentence dictated at every region of its technical app.
    public static let abstention: [EvaluationCase] = CorpusFile.cases(in: .technical, set: "abstention")
}
