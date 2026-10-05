// What is being written at the caret, beside which app it is written in.

/// What is being written, read from the document name and the text before the caret; never persisted.
public struct WritingIntent: Sendable, Equatable {
    /// The code language the evidence declares; `nil` when it says nothing, never a guess.
    public let language: CodeLanguage?

    public init(language: CodeLanguage?) {
        self.language = language
    }

    /// The intent a context read and its caret declare: the file extension first, then the caret's text.
    public init(app: AppContext, insertion: InsertionPoint) {
        let named = app.documentName.flatMap(CodeLanguage.from(fileName:))
        self.init(language: named ?? insertion.precedingText.flatMap(CodeLanguage.detect(fragment:)))
    }

    /// The intent when nothing on screen declares one.
    public static let unknown = WritingIntent(language: nil)
}
