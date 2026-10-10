/// Where a signal for a reading was read from; the override gate counts agreement across these, never across signals.
enum SignalProvenance: Hashable, Sendable, CaseIterable {
    /// The recogniser's own scores, such as the word heard surely elsewhere in the dictation.
    case recogniserAcoustics
    /// The recogniser wrote the doubted run as letters spelt out.
    case transcriptLetters
    /// The recogniser wrote the doubted run as more words than the other reading.
    case transcriptWordCount
    /// The text either side of the caret in the field being dictated into.
    case caretText
    /// The window's title and its selection.
    case windowText
    /// The user's persona list, which also feeds decode-time bias, candidates and the domain n-grams.
    case personaList
    /// Vocabulary shipped with the app.
    case shippedLexicon
    /// How a word is pronounced.
    case pronunciation

    /// How many independent signals agree: each provenance counts once, so one list read three ways is one signal.
    static func agreement(of signals: some Sequence<Sourced<some Hashable & Sendable>>) -> Int {
        Set(signals.map(\.provenance)).count
    }
}

/// One signal for a reading and its source, so the gate can tell two signals from one source read twice.
struct Sourced<Value: Hashable & Sendable>: Hashable, Sendable {
    /// What the signal says.
    let value: Value
    /// The source the signal comes from.
    let provenance: SignalProvenance
}
