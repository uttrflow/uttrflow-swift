// A clip, its kind and its picture record.

public import struct Foundation.Date
public import struct Foundation.UUID

/// What a copied thing is, detected rather than declared; decides the icon, the face and masking.
public enum ClipKind: String, Sendable, Equatable, CaseIterable, Codable {
    case text
    case link
    case code
    /// A key, token or connection string, masked in the list until deliberately revealed.
    case secret
    case colour
    case image
    /// A path to a file or folder on this Mac; its row can name the folder instead of repeating a prefix.
    case filePath
}

/// One thing the user copied, shaped to be identified at a glance and pasted without a second thought.
public struct Clip: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// Exactly what was copied, never trimmed or normalised, so what goes out is what came in.
    public let text: String
    public let kind: ClipKind
    /// Which language, when the clip is code and the answer is not a guess; decided once, on arrival.
    public let language: CodeLanguage?
    /// The formatted form as HTML, when the source had one; `text` is never derived from it.
    public let richText: String?
    /// The picture this clip is, as much of it as a row needs; the bytes live in a file beside the clipboard.
    public let image: ClipImage?
    public let copiedAt: Date
    /// When this clip was last reached for, which is what eviction ranks by; starts at `copiedAt`.
    public let lastUsedAt: Date
    /// How many times this exact thing has been copied, counting the first; the budget evicts by it.
    public let timesCopied: Int
    /// The application the clip came from, if known; shown as provenance and never a basis for a decision.
    public let source: String?
    /// Which tab this clip is under; its own field, since `source` can read "Dictation" by coincidence.
    public let origin: ClipOrigin

    /// A short handle the user typed, slash-prefixed by convention — `/pgprod` — so the clip can be found.
    public var alias: String?
    /// Which collection the clip is filed in; `nil` means it is still just history.
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
        // Defaulted from the arrival, not the clock, so a test's fixed date is not silently touched.
        self.lastUsedAt = lastUsedAt ?? copiedAt
        // Clamped, because a stored zero would sort below every real clip and be evicted first.
        self.timesCopied = max(timesCopied, 1)
        self.source = source
        self.origin = origin
        self.alias = alias
        self.category = category
        self.isPinned = isPinned
    }

    /// Hand-written so a clipboard from before `timesCopied` still decodes rather than being discarded.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let source = try values.decodeIfPresent(String.self, forKey: .source)
        // A clipboard with no origins reads `source` once, here, so dictations stay in their own tab.
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

    /// The same clip, reached for at `moment`; a whole copy because `lastUsedAt` is `let`.
    public func used(at moment: Date) -> Clip {
        Clip(
            id: id, text: text, kind: kind, copiedAt: copiedAt, source: source, origin: origin,
            lastUsedAt: moment, language: language, richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// Whether the user deliberately kept this, which retention never ages out.
    public var isKept: Bool { alias != nil || category != nil || isPinned }

    /// E1 — whether this clip carries formatting worth telling the user about.
    public var isFormatted: Bool { richText != nil }

    /// One line for the list, so a multi-line clip never grows its row.
    public var summary: String {
        text.split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

/// A picture on the clipboard, as much of it as a row needs; `file` is relative to the clipboard's folder.
public struct ClipImage: Sendable, Equatable, Codable {
    public let file: String
    public let width: Int
    public let height: Int
    /// What the file weighs, so the row can say so without reading it.
    public let bytes: Int
    /// A digest of the picture's bytes, so the same screenshot copied twice merges; `nil` for older stores.
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
