public import struct Foundation.Date
public import struct Foundation.UUID

/// What a copied thing turns out to be.
///
/// Detected rather than declared, because nobody is going to tell the app what they just
/// copied. The kind decides the icon, whether the text is set in a monospaced face, and —
/// for ``secret`` — whether it is legible on screen at all.
public enum ClipKind: String, Sendable, Equatable, CaseIterable, Codable {
    case text
    case link
    case code
    /// A key, token or connection string. Masked in the list until deliberately revealed,
    /// because this panel is opened in meetings and on shared screens.
    case secret
    case colour
    case image
    /// K5 — a path to a file or folder on this Mac.
    ///
    /// Its own kind rather than text, because what the user does with it differs: a path
    /// is pasted into a terminal or a dialog, and the row can say which folder it is in
    /// instead of repeating a prefix shared by every path they have ever copied.
    case filePath
}

/// One thing the user copied.
///
/// The whole product is three keystrokes long — open, arrow down, Return — so everything
/// here exists to make a clip identifiable at a glance in a list, and pasteable without a
/// second thought.
public struct Clip: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// Exactly what was copied. Never trimmed, never normalised: what goes back out has
    /// to be what came in, or the app has quietly edited someone's work.
    public let text: String
    public let kind: ClipKind
    /// D1 — which language, when the clip is code and the answer is not a guess.
    ///
    /// `nil` covers three different things on purpose: the clip is not code, it is code
    /// in a language nothing here recognises, or it is code that reads equally as two
    /// languages. All three mean the same to everything downstream — draw no chip — and
    /// distinguishing them would only invite somewhere to print a label.
    ///
    /// Decided once, when the clip arrives, and stored. Deciding it while drawing would
    /// run the detector over every clip in the history on every keystroke, and the panel
    /// has to open instantly or the three keystrokes are not worth having.
    public let language: CodeLanguage?
    /// E — the formatted form of the clip, when it was copied from somewhere that had one.
    ///
    /// HTML, because that is what the pasteboard carries and what `NSAttributedString`
    /// round-trips through. ``text`` is always the plain form and is never derived from
    /// this: a clip must be pasteable into a terminal without anything having to convert
    /// anything first, and the conversion that runs at paste time is the one that can fail.
    ///
    /// Having both is what makes E2 and E3 the platform's problem rather than ours. Both
    /// flavours go on the pasteboard together and the receiving application takes the one
    /// it understands — Pages gets the headings, a code editor gets the words.
    public let richText: String?
    /// K4 — the picture this clip is, when it is one.
    ///
    /// Only what a row needs to draw itself. The bytes live in a file beside the
    /// clipboard, not in this record: the whole list is read to open the panel and
    /// rewritten on every copy, so a single screenshot inlined here would be megabytes
    /// read and written on every keystroke, for a thumbnail nobody is looking at.
    public let image: ClipImage?
    public let copiedAt: Date
    /// When this clip was last *reached for* — pasted, inserted, put back on the
    /// clipboard — as opposed to when it arrived.
    ///
    /// The two are different questions and the eviction policy wants this one. Ranking by
    /// arrival throws away the clip you have leaned on all week because you happened to
    /// copy it on Monday; ranking by how often it was copied, which is what this used to
    /// do, credits the value you copied twenty times last month over the one you have
    /// pasted twice this morning. Least *recently used* is the rule people expect from a
    /// cache, and it needs a record of use.
    ///
    /// Starts at ``copiedAt``, because arriving is a use: a clip you have just copied is
    /// the most recently touched thing in the list, which is exactly what it should be.
    public let lastUsedAt: Date
    /// How many times this exact thing has been copied, counting the first.
    ///
    /// A clipboard is a hash map with a clock on it: copying something already in the
    /// history is not a new clip, it is the same clip happening again. The count is what
    /// lets the store answer "which of these does the user actually reach for" without
    /// guessing from age alone — see `ClipboardStore.budget`, which evicts by it.
    ///
    /// Starts at one, because a clip exists only because it was copied once.
    public let timesCopied: Int
    /// The application it was copied from, when that was known. Shown as provenance, and
    /// never used to decide anything.
    public let source: String?
    /// Which of the two lists this clip belongs to — what the user copied, or what
    /// Uttrflow made. See ``ClipOrigin`` for why there are two.
    ///
    /// Unlike ``source`` this *does* decide something: which tab the clip is under. It is
    /// therefore its own field rather than a reading of the provenance string, which is
    /// whatever application happened to be in front and can be the word "Dictation" by
    /// coincidence.
    public let origin: ClipOrigin

    /// A short handle the user typed, so this can be found without remembering its
    /// contents. Slash-prefixed by convention — `/pgprod` — which says "type me".
    public var alias: String?
    /// Which collection it was filed into. `nil` means it is still just history.
    public var category: String?
    public var isPinned: Bool

    public init(
        id: UUID = UUID(), text: String, kind: ClipKind, copiedAt: Date, source: String? = nil,
        origin: ClipOrigin = .copied,
        lastUsedAt: Date? = nil,
        language: CodeLanguage? = nil,
        richText: String? = nil,
        image: ClipImage? = nil,
        alias: String? = nil, category: String? = nil, isPinned: Bool = false,
        timesCopied: Int = 1
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.language = language
        self.richText = richText
        self.image = image
        self.copiedAt = copiedAt
        // Defaulted from the arrival rather than from the clock, so a clip built with a
        // fixed date in a test is not silently touched by the moment the test ran.
        self.lastUsedAt = lastUsedAt ?? copiedAt
        // Clamped rather than trusted: a stored zero would sort below every real clip and
        // be evicted first, which is the opposite of what a hand-edited file meant.
        self.timesCopied = max(timesCopied, 1)
        self.source = source
        self.origin = origin
        self.alias = alias
        self.category = category
        self.isPinned = isPinned
    }

    /// Written by hand only because a synthesised decoder refuses a clipboard that
    /// predates ``timesCopied``.
    ///
    /// Swift's generated `init(from:)` requires every non-optional key to be present and
    /// ignores the property's default, so adding one `Int` would make every clipboard
    /// already on disk unreadable — and this store discards a file it cannot read. That
    /// is somebody's whole history, thrown away by a field that was meant to save space.
    /// Everything else keeps the generated behaviour.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let source = try values.decodeIfPresent(String.self, forKey: .source)
        // A clipboard written before the two lists existed has no origin on any of its
        // clips, and every one of them would default to ⌘C — which would put somebody's
        // whole dictation history into the tab that exists to keep it out. The provenance
        // string is the only evidence left, so it is read once, here, and never again.
        let origin =
            try values.decodeIfPresent(ClipOrigin.self, forKey: .origin)
            ?? (source == ClipOrigin.dictationSource ? .uttrflow : .copied)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            text: values.decode(String.self, forKey: .text),
            kind: values.decode(ClipKind.self, forKey: .kind),
            copiedAt: values.decode(Date.self, forKey: .copiedAt),
            source: source,
            origin: origin,
            lastUsedAt: values.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            language: values.decodeIfPresent(CodeLanguage.self, forKey: .language),
            richText: values.decodeIfPresent(String.self, forKey: .richText),
            image: values.decodeIfPresent(ClipImage.self, forKey: .image),
            alias: values.decodeIfPresent(String.self, forKey: .alias),
            category: values.decodeIfPresent(String.self, forKey: .category),
            isPinned: values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            timesCopied: values.decodeIfPresent(Int.self, forKey: .timesCopied) ?? 1)
    }

    /// The same clip, reached for at a given moment.
    ///
    /// A whole copy because ``lastUsedAt`` is `let` for the reason every other fact about
    /// a clip is: what was copied does not change, and the one field that legitimately
    /// moves should move somewhere a reader can see it happening.
    public func used(at moment: Date) -> Clip {
        Clip(
            id: id, text: text, kind: kind, copiedAt: copiedAt, source: source, origin: origin,
            lastUsedAt: moment, language: language, richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// Whether the user deliberately kept this, as opposed to merely having copied it.
    ///
    /// The distinction drives retention: history ages out on a clock, and anything the
    /// user named, filed or pinned does not. Losing a clip you saved would be the worst
    /// thing this app could do.
    public var isKept: Bool { alias != nil || category != nil || isPinned }

    /// E1 — whether this clip carries formatting worth telling the user about.
    public var isFormatted: Bool { richText != nil }

    /// One line for the list, with the newlines taken out.
    ///
    /// A multi-line clip must not grow its row — the list is scanned with arrow keys and
    /// every row has to be the same height for that to feel predictable.
    public var summary: String {
        text.split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// K4 — a picture on the clipboard, as much of it as a row needs.
///
/// The file name is relative to the folder the clipboard itself is kept in, so moving or
/// copying that folder keeps the pictures with their clips. An absolute path would break
/// the first time somebody's home directory was named differently.
public struct ClipImage: Sendable, Equatable, Codable {
    public let file: String
    public let width: Int
    public let height: Int
    /// What the file weighs, so the row can say so without reading it.
    public let bytes: Int
    /// A digest of the picture's bytes, so the same screenshot copied twice can be
    /// recognised as the same clip.
    ///
    /// Pictures used to be exempt from merging altogether, because the only thing being
    /// compared was `text` — and every picture's text is empty, so matching on it made
    /// every screenshot the same clip as the last. The answer is not to give up on
    /// merging but to compare the thing that actually differs.
    ///
    /// Optional: a store written before this existed has none, and those pictures simply
    /// go on never merging rather than the file being refused.
    public let sha: String?

    public init(file: String, width: Int, height: Int, bytes: Int, sha: String? = nil) {
        self.file = file
        self.width = width
        self.height = height
        self.bytes = bytes
        self.sha = sha
    }

    /// "1024 × 768", with the multiplication sign rather than a letter x.
    public var dimensions: String { "\(width) × \(height)" }
}
