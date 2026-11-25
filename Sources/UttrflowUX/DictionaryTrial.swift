// The Dictionary page's "Try it" result: what a word does to a sentence.

public import Foundation

/// One spoken try of a word: whose it is and how far it got.
public struct DictionaryTrial: Sendable, Equatable {
    /// The word a try is of.
    public enum Subject: Sendable, Equatable {
        /// What is typed in the open editor.
        case draft
        /// How the open editor's word is said, heard to fill its "Say it like".
        case draftPronunciation
        /// A saved word.
        case word(UUID)
    }

    /// How far a try got.
    public enum Phase: Sendable, Equatable {
        /// Recording the word being said.
        case listening
        /// Decoding the clip.
        case checking
        /// The probe's one line, and the heard words a miss offers as "Say it like".
        case result(line: String, offer: String?)
        /// Why the try could not run, in words.
        case failed(String)
    }

    /// Whose try this is.
    public let subject: Subject
    /// How far it got.
    public let phase: Phase

    /// Builds a try from its parts.
    public init(subject: Subject, phase: Phase) {
        self.subject = subject
        self.phase = phase
    }
}

/// A try's result row: one line, whether it is still going, and the "Say it like" a miss offers.
public struct DictionaryTrialLine: Sendable, Equatable {
    /// What the row says.
    public let text: String
    /// Whether the try is still listening or checking.
    public let isBusy: Bool
    /// Fills "Say it like" with what was heard; present only on a miss.
    public let offer: MainAction?

    /// Builds the row from its parts.
    public init(text: String, isBusy: Bool, offer: MainAction?) {
        self.text = text
        self.isBusy = isBusy
        self.offer = offer
    }
}
