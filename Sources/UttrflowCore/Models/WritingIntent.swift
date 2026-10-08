// What is being written at the caret, beside which app it is written in.

/// What is being written, read from the document name, the field and the text before the caret; never persisted.
public struct WritingIntent: Sendable, Equatable {
    /// The code language the evidence declares; `nil` when it says nothing, never a guess.
    public let language: CodeLanguage?
    /// What the focused field is for.
    public let fieldRole: FieldRole
    /// What kind of text the caret stands in: code, a string, a comment, prose or unrecognised.
    public let region: CaretStructure.Region

    public init(
        language: CodeLanguage?, fieldRole: FieldRole = .unknown,
        region: CaretStructure.Region = .unrecognised
    ) {
        self.language = language
        self.fieldRole = fieldRole
        self.region = region
    }

    /// The intent a context read and its caret declare: the file extension first, then the caret's text.
    public init(app: AppContext, insertion: InsertionPoint) {
        let named = app.documentName.flatMap(CodeLanguage.from(fileName:))
        self.init(
            language: named ?? insertion.precedingText.flatMap(CodeLanguage.detect(fragment:)),
            fieldRole: app.fieldRole,
            region: CaretStructure.region(
                precedingText: insertion.precedingText, documentName: app.documentName))
    }

    /// The intent when nothing on screen declares one.
    public static let unknown = WritingIntent(language: nil)
}
