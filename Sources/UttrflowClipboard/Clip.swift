// A clip, its kind and its picture record.

public import struct Foundation.Date
public import struct Foundation.UUID
public import UttrflowCore

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
    /// JSON fields understood by this build; unknown fields make an older build's rewrite unsafe.
    package static let persistedJSONKeys: Set<String> = [
        "id", "text", "kind", "language", "richText", "image", "copiedAt", "lastUsedAt",
        "lastUsedOrder", "timesCopied", "source", "origin", "dictations", "dictatedText",
        "alias", "category", "isPinned",
    ]

    private static let summaryCharacterLimit = 300
    /// Full-text previews stay small even when a copied document is near the clipboard budget.
    public static let previewCharacterLimit = 10_000

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
    /// The wall-clock time of the latest use; eviction ranks by `lastUsedOrder` instead.
    public let lastUsedAt: Date
    /// The persisted, monotonic order in which this clip was last used.
    public let lastUsedOrder: UInt64?
    /// How many times this exact thing has been copied, counting the first; the budget evicts by it.
    public let timesCopied: Int
    /// The application the clip came from, if known; shown as provenance and never a basis for a decision.
    public let source: String?
    /// Which tab this clip is under; its own field, since `source` can read "Dictation" by coincidence.
    public let origin: ClipOrigin
    /// The dictations this clip copies, so deleting one deletes the clip whatever its text says now.
    public let dictations: [UUID]
    /// The words a dictation copy older than `dictations` was made with, kept so an edit cannot unlink it.
    public let dictatedText: String?

    /// A short handle the user typed, slash-prefixed by convention — `/pgprod` — so the clip can be found.
    public var alias: String?
    /// Which collection the clip is filed in; `nil` means it is still just history.
    public var category: String?
    public var isPinned: Bool

    public init(
        id: UUID = UUID(), text: String, kind: ClipKind, copiedAt: Date, source: String? = nil,
        origin: ClipOrigin = .copied,
        dictations: [UUID] = [],
        dictatedText: String? = nil,
        lastUsedAt: Date? = nil,
        lastUsedOrder: UInt64? = nil,
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
        self.lastUsedOrder = lastUsedOrder
        // Clamped, because a stored zero would sort below every real clip and be evicted first.
        self.timesCopied = max(timesCopied, 1)
        self.source = source
        self.origin = origin
        self.dictations = dictations
        self.dictatedText = dictatedText
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
            dictations: values.decodeIfPresent([UUID].self, forKey: .dictations) ?? [],
            dictatedText: values.decodeIfPresent(String.self, forKey: .dictatedText),
            lastUsedAt: values.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            lastUsedOrder: values.decodeIfPresent(UInt64.self, forKey: .lastUsedOrder),
            language: values.decodeIfPresent(CodeLanguage.self, forKey: .language),
            richText: values.decodeIfPresent(String.self, forKey: .richText),
            image: values.decodeIfPresent(ClipImage.self, forKey: .image),
            alias: values.decodeIfPresent(String.self, forKey: .alias),
            category: values.decodeIfPresent(String.self, forKey: .category),
            isPinned: values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false,
            timesCopied: values.decodeIfPresent(Int.self, forKey: .timesCopied) ?? 1)
    }

    /// The same clip, reached for at `moment`; a whole copy because `lastUsedAt` is `let`.
    public func used(at moment: Date, order: UInt64) -> Clip {
        Clip(
            id: id, text: text, kind: kind, copiedAt: copiedAt, source: source, origin: origin,
            dictations: dictations, dictatedText: dictatedText, lastUsedAt: moment,
            lastUsedOrder: order, language: language,
            richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// The same clip reached for at `moment`, preserving its current eviction order.
    public func used(at moment: Date) -> Clip {
        used(at: moment, order: lastUsedOrder ?? 0)
    }

    /// The same clip stamped freshly at `moment`, so an un-keep does not also age the clip out.
    public func recopied(at moment: Date, order: UInt64) -> Clip {
        Clip(
            id: id, text: text, kind: kind, copiedAt: moment, source: source, origin: origin,
            dictations: dictations, dictatedText: dictatedText, lastUsedOrder: order, language: language,
            richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// The same clip carrying its stable eviction order.
    func orderedForEviction(_ order: UInt64) -> Clip {
        Clip(
            id: id, text: text, kind: kind, copiedAt: copiedAt, source: source, origin: origin,
            dictations: dictations, dictatedText: dictatedText, lastUsedAt: lastUsedAt,
            lastUsedOrder: order, language: language, richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// Replaces only the detector-owned classification fields while preserving the clip's identity and edits.
    func reclassified(as classification: ClipClassification) -> Clip {
        Clip(
            id: id, text: text, kind: classification.kind, copiedAt: copiedAt, source: source, origin: origin,
            dictations: dictations, dictatedText: dictatedText, lastUsedAt: lastUsedAt,
            lastUsedOrder: lastUsedOrder, language: classification.language, richText: richText, image: image,
            alias: alias, category: category, isPinned: isPinned, timesCopied: timesCopied)
    }

    /// Whether this is the copy of that dictation; a clip older than the link is matched on its words.
    public func isCopy(ofDictation id: UUID, saying spoken: String?) -> Bool {
        guard origin == .uttrflow else { return false }
        // A clip typed into the panel is Uttrflow's too, and only a dictation's copy is labelled as one.
        if dictations.isEmpty { return isUnlinkedDictationCopy && spoken == (dictatedText ?? text) }
        return dictations.contains(id)
    }

    /// Whether this is a dictation's copy from before `dictations`, which only its words can find.
    public var isUnlinkedDictationCopy: Bool {
        origin == .uttrflow && dictations.isEmpty && source == ClipOrigin.dictationSource
    }

    /// Whether the user deliberately kept this, which retention never ages out.
    public var isKept: Bool { alias != nil || category != nil || isPinned }

    /// E1 — whether this clip carries formatting worth telling the user about.
    public var isFormatted: Bool { richText != nil }

    /// One bounded line for the list, so a clip never grows its row.
    public var summary: String {
        var firstLine = ""
        firstLine.reserveCapacity(Self.summaryCharacterLimit)
        for character in text.prefix(Self.summaryCharacterLimit) {
            if character.isNewline {
                if firstLine.isEmpty { continue }
                break
            }
            firstLine.append(character)
        }
        let visible = firstLine.trimmingCharacters(in: .whitespaces)
        if !visible.isEmpty { return visible }
        guard !text.isEmpty else { return "" }
        return "Whitespace only · \(text.count) characters"
    }

    /// The number of following lines, counting a trailing newline as content that will be pasted.
    public var additionalLineCount: Int {
        text.reduce(into: 0) { count, character in
            if character.isNewline { count += 1 }
        }
    }

    /// The bounded text offered before paste; a suffix makes truncation explicit.
    public var preview: String {
        guard text.count > Self.previewCharacterLimit else { return text }
        return String(text.prefix(Self.previewCharacterLimit)) + "\n… preview truncated"
    }
}

/// A picture on the clipboard, as much of it as a row needs; `file` is relative to the clipboard's folder.
public struct ClipImage: Sendable, Equatable, Codable {
    /// JSON fields understood by this build; unknown fields make an older build's rewrite unsafe.
    package static let persistedJSONKeys: Set<String> = ["file", "width", "height", "bytes", "sha"]

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

    /// Whether a stored file name is a single path component, so it can only name a file inside the Images folder.
    static func isConfinedFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    /// "1024 × 768", with the multiplication sign rather than a letter x.
    public var dimensions: String { "\(width) × \(height)" }
}
