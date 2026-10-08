/// Which pool of memory a clip is charged to; derived from the clip, never stored on it.
public enum ClipClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// A clip the user named, filed or pinned; never evicted by anything, so this pool has no tier.
    case kept
    /// Text the user pressed ⌘C on.
    case copied
    /// What Uttrflow made — a clip the user kept from History or the panel.
    case dictation
    /// Pictures, whoever put them there.
    case images

    /// Kept first, so a pinned screenshot outlives the pictures' window; then the kind, whatever made it.
    public init(of clip: Clip) {
        if clip.isKept {
            self = .kept
        } else if clip.kind == .image || clip.image != nil {
            self = .images
        } else {
            self = clip.origin == .uttrflow ? .dictation : .copied
        }
    }

    /// Whether anything at all may remove a clip in this pool to make room.
    public var isEvictable: Bool { self != .kept }
}

/// What one pool of clips may cost, and how it is cut back. See Docs/clipboard-budget.md.
public struct ClipboardTier: Sendable, Equatable {
    /// The most memory this pool may hold, in bytes: strings for text, decoded thumbnails for pictures.
    public let bytes: Int

    /// The most records this pool may hold; the file is rewritten whole on every copy, so length costs too.
    public let items: Int

    /// How many days an unkept clip survives, or `nil` to take the window from the user's settings.
    public let days: Int?

    public init(bytes: Int, items: Int, days: Int? = nil) {
        self.bytes = max(0, bytes)
        self.items = max(0, items)
        self.days = days
    }
}

/// Every number that decides how much memory the clipboard may use. See Docs/clipboard-budget.md.
public struct ClipboardBudget: Sendable, Equatable {
    /// The most memory every pool together may hold; a test checks the tiers against it.
    public let ceiling: Int

    public let copied: ClipboardTier
    public let dictation: ClipboardTier
    public let images: ClipboardTier

    /// The largest single clip kept at all; the one number that stops unbounded growth.
    public let largestClip: Int

    /// The most pixels a copied picture's header may claim; one over it is never decoded.
    public let largestPicture: Int

    /// The longest edge, in pixels, a converted picture is decoded and stored at.
    public let pictureEdge: Int

    /// The most disk the pictures may take.
    public let disk: Int

    public init(
        ceiling: Int, copied: ClipboardTier, dictation: ClipboardTier, images: ClipboardTier,
        largestClip: Int, largestPicture: Int, pictureEdge: Int, disk: Int
    ) {
        self.ceiling = ceiling
        self.copied = copied
        self.dictation = dictation
        self.images = images
        self.largestClip = largestClip
        self.largestPicture = largestPicture
        self.pictureEdge = pictureEdge
        self.disk = disk
    }

    /// The policy for a pool, or `nil` for `kept`, whose absence of a bound has to be structural.
    public func tier(for pool: ClipClass) -> ClipboardTier? {
        switch pool {
        case .kept: nil
        case .copied: copied
        case .dictation: dictation
        case .images: images
        }
    }

    /// What the tiers add up to, compared against `ceiling` by a test rather than clamped here.
    public var claimed: Int { copied.bytes + dictation.bytes + images.bytes }

    /// Whether a write leaves the kept pictures within `disk`, or at least no further past it than before.
    func fitsKeptPictures(_ clips: [Clip], replacing previous: [Clip]) -> Bool {
        guard disk > 0 else { return true }
        let bytes = Self.keptPictureBytes(in: clips)
        return bytes <= disk || bytes <= Self.keptPictureBytes(in: previous)
    }

    /// What the kept pictures take on disk; eviction never touches them, so only a refusal bounds it.
    private static func keptPictureBytes(in clips: [Clip]) -> Int {
        clips.reduce(0) { $1.isKept ? $0 + ($1.image?.bytes ?? 0) : $0 }
    }

    /// Whether a clip weighing this many bytes of text and formatted text stays within `largestClip`.
    public func fitsLargestClip(weighing bytes: Int) -> Bool {
        largestClip <= 0 || bytes <= largestClip
    }

    /// Whether a positive image header stays within this budget's pixel bound.
    public func fitsPicture(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0 else { return false }
        guard largestPicture > 0 else { return true }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return !overflow && pixels <= largestPicture
    }

    /// The shape this build ships with: 44 MB claimed against a 64 MB ceiling. See Docs/clipboard-budget.md.
    public static let standard = ClipboardBudget(
        ceiling: 64 * 1_000_000,
        copied: ClipboardTier(bytes: 8 * 1_000_000, items: 500),
        dictation: ClipboardTier(bytes: 4 * 1_000_000, items: 500),
        images: ClipboardTier(bytes: 32 * 1_000_000, items: 500, days: 7),
        largestClip: 2 * 1_000_000,
        largestPicture: 150 * 1_000_000,
        pictureEdge: 4096,
        disk: 1_000_000_000)
}
