public import struct Foundation.Date
public import struct Foundation.UUID

/// One finished dictation, as it is kept.
///
/// Carries what the interface has always wanted to show and never had a source for:
/// which application the words went into, and how long the speaker talked. Both are
/// known at the moment of dictation and were being discarded, which is why the history
/// artboard's app tile and duration chip had nothing behind them.
///
/// There is deliberately no audio here, and no path to any. Nothing in Uttrflow writes a
/// recording to disk, so a field for one would be an invitation to start.
public struct DictationRecord: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// The text that was inserted, after tidying.
    ///
    /// Settable inside this module and nowhere else. ``undoing(_:)`` has to hand back a
    /// record whose text has one change spliced out of it, and it does that by copying
    /// this value and changing the copy — never by calling the initialiser with a list
    /// of the fields it happens to remember. A `let` would force the second, which is
    /// the shape of bug that has now dropped ``isFlagged`` here and `spokenFor` in the
    /// app: a constructor silently substitutes a default for every field the caller
    /// forgot, and nothing warns. Nothing outside `UttrflowHistory` may rewrite a
    /// dictation's words, so the setter stops at the module boundary.
    public internal(set) var text: String
    public let when: Date
    /// The application the text went into, when that was known.
    public let applicationName: String?
    /// That application's bundle identifier, when the context knew it.
    ///
    /// Optional for the same reason `changes` is: a history written before this field
    /// existed goes on decoding, and those dictations simply have no identifier. The
    /// name is what a row is labelled with; this is what it can be looked up by, which
    /// is the difference between finding Claude's icon and finding whichever bundle
    /// happens to be called Claude.
    public let applicationIdentifier: String?
    /// How long the speaker talked, when it was measured.
    public let spokenFor: Duration?
    /// What Uttrflow changed about what was said, when that is known.
    ///
    /// Optional, and the distinction it draws is load-bearing. Present and empty means
    /// "this dictation came out exactly as it was spoken"; absent means "nobody was
    /// keeping a record when this was written" — either a file from a build before
    /// changes were kept, or a dictation whose insertion failed and which therefore
    /// never reported what had been applied. Collapsing the two would let
    /// ``DictationPresenter/accuracy(of:snapshot:)`` count an unmeasured dictation as a perfect
    /// one, which is the accuracy figure quietly inventing its own denominator.
    ///
    /// Being optional is also what lets a history written before this field existed go
    /// on decoding: the synthesised decoder asks for it and takes its absence for an
    /// answer.
    public var changes: RecordedChanges?
    /// Whether the user has said this one came out wrong.
    ///
    /// The only judgement in the record that Uttrflow did not make. Everything else here
    /// is what the app observed; this is what the person who was actually there thinks
    /// of the result, and there is no measurement that substitutes for it.
    ///
    /// Deliberately not optional, unlike ``changes``. There is no third state to
    /// preserve: a dictation nobody flagged and a dictation from before flags existed
    /// are the same fact — the user has not complained about it. Decoding treats the
    /// missing key as `false` for exactly that reason.
    public var isFlagged: Bool

    public init(
        id: UUID = UUID(), text: String, when: Date, applicationName: String? = nil,
        applicationIdentifier: String? = nil, spokenFor: Duration? = nil,
        changes: RecordedChanges? = nil, isFlagged: Bool = false
    ) {
        self.id = id
        self.text = text
        self.when = when
        self.applicationName = applicationName
        self.applicationIdentifier = applicationIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
        self.isFlagged = isFlagged
    }

    /// Written by hand only because a synthesised decoder refuses a history that predates
    /// ``isFlagged``.
    ///
    /// Swift's generated `init(from:)` requires every non-optional key to be present and
    /// ignores the property's default, so adding one `Bool` would make every file already
    /// on disk unreadable — and this store discards a file it cannot read. Everything
    /// else keeps the generated behaviour.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        when = try values.decode(Date.self, forKey: .when)
        applicationName = try values.decodeIfPresent(String.self, forKey: .applicationName)
        applicationIdentifier = try values.decodeIfPresent(
            String.self, forKey: .applicationIdentifier)
        spokenFor = try values.decodeIfPresent(Duration.self, forKey: .spokenFor)
        changes = try values.decodeIfPresent(RecordedChanges.self, forKey: .changes)
        isFlagged = try values.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
    }

    /// Whether this is still within `days` of `now`, and so may still be shown.
    ///
    /// Asked of the record rather than computed at each call site, because "deleted
    /// after N days" is a promise made to the user in three places and three
    /// implementations of it is three chances to keep something too long.
    public func survives(days: Int, now: Date) -> Bool {
        guard days > 0 else { return false }
        return when.addingTimeInterval(Double(days) * 86_400) > now
    }
}
