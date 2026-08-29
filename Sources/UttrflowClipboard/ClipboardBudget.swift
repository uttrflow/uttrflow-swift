/// Which pool of memory a clip is charged to.
///
/// Four, because the four behave nothing alike and a single policy over them is a policy
/// tuned for whichever is loudest. A ⌘C is small, frequent and often a repeat of
/// something already held; a dictation is small and arrives on its own clock; a picture
/// is four orders of magnitude larger than either and is the only one that can make the
/// app noticeable on somebody's machine. And a clip the user *kept* is not history at
/// all — see ``kept``.
///
/// Derived from the clip, never stored on it. A stored class would be a second answer to
/// a question ``Clip/isKept``, ``ClipKind`` and ``ClipOrigin`` already answer between
/// them, and the two could disagree after a migration — or, worse, after the user pinned
/// something.
public enum ClipClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// A clip the user named, filed or pinned. **Never evicted, by anything.**
    ///
    /// Not a pool with a generous quota — a pool with no quota, no window and no
    /// replacement policy. Naming a clip, tagging it into a collection or pinning it is
    /// the user saying "I will want this later", and the whole value of saying so is that
    /// it survives every rule that applies to the things they did not say it about.
    /// Losing one would be the worst thing this app could do.
    ///
    /// The honest consequence, stated here because it is the one hole in the ceiling: a
    /// pool with no bound cannot be bounded. ``ClipboardBudget/ceiling`` is a promise
    /// about *history*, not about what somebody deliberately saved. Someone who pins two
    /// gigabytes of screenshots has asked for two gigabytes of screenshots.
    ///
    /// These are also the clips destined to outlive this file. When kept clips move to a
    /// database they move as a set, which is another reason to name them as their own
    /// class now rather than to discover them later as "everything the policies skipped".
    case kept
    /// Text the user pressed ⌘C on.
    case copied
    /// What Uttrflow made — a dictation, or a clip kept from the panel.
    case dictation
    /// Pictures, whoever put them there.
    case images

    /// Kept is asked first, and nothing after it can override it: a pinned screenshot is
    /// kept, not a picture, or the pictures' seven-day window would delete the very thing
    /// the pin was for.
    ///
    /// Then the kind, because a picture is a picture whatever made it: its cost is its
    /// pixels, and charging a dictated screenshot to the dictation pool would let one
    /// image overrun a quota sized for sentences.
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

    public var title: String {
        switch self {
        case .kept: "Saved"
        case .copied: "Copied"
        case .dictation: "From Uttrflow"
        case .images: "Pictures"
        }
    }
}

/// What one pool of clips may cost, and how it is cut back when it costs more.
///
/// Every field is a number somebody chose, so every field says who chose it and against
/// what. A quota with no reasoning attached is a number the next person is afraid to
/// change, which is how a budget becomes folklore.
public struct ClipboardTier: Sendable, Equatable {
    /// The most memory this pool may hold, in bytes.
    ///
    /// Memory, not disk — what the process is actually carrying. For the two text pools
    /// that is the strings themselves; for pictures it is the decoded thumbnails, because
    /// the files never enter the process at full size.
    public let bytes: Int

    /// The most records this pool may hold.
    ///
    /// Kept alongside ``bytes`` rather than replaced by it, because the two bound
    /// different failures. Bytes stop the pool from being *large*; the count stops the
    /// file from being *long*, and the file is rewritten whole on every copy — a hundred
    /// thousand tiny clips weigh nothing and would still make every ⌘C a slow write.
    public let items: Int

    /// How many days an unkept clip in this pool survives, or `nil` to take the window
    /// from the user's settings.
    ///
    /// Pictures have their own, shorter by default: a screenshot is worth keeping for as
    /// long as you are working on the thing you screenshotted, and it costs a thousand
    /// times what a sentence costs to keep for the same fortnight.
    public let days: Int?

    public init(bytes: Int, items: Int, days: Int? = nil) {
        self.bytes = max(0, bytes)
        self.items = max(0, items)
        self.days = days
    }
}

/// Every number that decides how much of this Mac's memory the clipboard may use.
///
/// One value, in one file, so that changing the shape of the cache for a build is an edit
/// to a literal rather than an archaeology exercise across four types. Not a user
/// setting and not meant to become one: nobody opening a clipboard panel has an opinion
/// about a thumbnail cache in megabytes, and a preference nobody can answer is a
/// preference that ships set wrong.
///
/// **The numbers are what the measurements say, not what a plan hoped.** A live clipboard
/// of fifty-five clips weighs ten kilobytes of text; five hundred of them is under a
/// megabyte. The quotas below are therefore generous by a factor of ten against real use
/// and still add up to a fraction of what the app costs to have open at all — which is the
/// honest shape of this problem, and the reason ``largestClip`` matters more than any of
/// them.
public struct ClipboardBudget: Sendable, Equatable {
    /// The most memory every pool together may hold.
    ///
    /// A ceiling rather than a sum: the tiers are checked against it, so raising one
    /// without lowering another is caught by a test rather than discovered on a user's
    /// machine. See `ClipboardBudgetTests`.
    public let ceiling: Int

    public let copied: ClipboardTier
    public let dictation: ClipboardTier
    public let images: ClipboardTier

    /// The largest single clip that will be kept at all.
    ///
    /// This is the one number here that stops unbounded growth, and no replacement policy
    /// can do its job. Every eviction rule below assumes many small things, so it evicts
    /// *many* — and one copied log file is one thing. Nothing capped the size of a clip
    /// before this: a two-hundred-megabyte copy went into the list and stayed, and since
    /// the whole file is rewritten atomically on every copy, it also made every later ⌘C
    /// a two-hundred-megabyte write.
    ///
    /// Two megabytes is about a million characters. Nothing that long is read in a panel
    /// of forty-point rows, so what is lost is a history entry for something that is still
    /// on the system clipboard and can still be pasted. That trade is worth stating out
    /// loud, because it is the only case where Uttrflow declines to remember something on
    /// purpose.
    ///
    /// It applies on the way in, to history. It cannot apply to ``ClipClass/kept``,
    /// which is nothing to do with generosity: a clip becomes kept by being named or
    /// pinned *after* it is already held, so it was under this cap when it arrived.
    public let largestClip: Int

    /// The most disk the pictures may take. Unchanged in kind from what it always was;
    /// it lives here now so that every bound is in one place.
    public let disk: Int

    public init(
        ceiling: Int, copied: ClipboardTier, dictation: ClipboardTier, images: ClipboardTier,
        largestClip: Int, disk: Int
    ) {
        self.ceiling = ceiling
        self.copied = copied
        self.dictation = dictation
        self.images = images
        self.largestClip = largestClip
        self.disk = disk
    }

    /// The policy for a pool, or `nil` where there is deliberately none.
    ///
    /// `nil` for ``ClipClass/kept`` rather than a tier with enormous numbers in it. A
    /// large quota is still a quota, and it would be reached one day by exactly the
    /// person who had most carefully saved things; the absence has to be structural or it
    /// is not a promise.
    public func tier(for pool: ClipClass) -> ClipboardTier? {
        switch pool {
        case .kept: nil
        case .copied: copied
        case .dictation: dictation
        case .images: images
        }
    }

    /// What the tiers add up to. Compared against ``ceiling`` by a test rather than
    /// clamped here: a budget that quietly shrank the numbers it was given would be a
    /// budget nobody could reason about from reading it.
    public var claimed: Int { copied.bytes + dictation.bytes + images.bytes }

    /// The same budget with one bound narrowed across every pool.
    ///
    /// For tests, which are about whether a rule fires rather than about the number it
    /// fires at — a test that had to spell out four tiers to say "cap it at three" would
    /// be a test whose subject was the budget's shape.
    public func limiting(
        items: Int? = nil, bytes: Int? = nil, days: Int? = nil, largestClip: Int? = nil,
        disk: Int? = nil
    ) -> ClipboardBudget {
        func narrowed(_ tier: ClipboardTier) -> ClipboardTier {
            ClipboardTier(
                bytes: bytes ?? tier.bytes, items: items ?? tier.items, days: days ?? tier.days)
        }
        return ClipboardBudget(
            ceiling: ceiling, copied: narrowed(copied), dictation: narrowed(dictation),
            images: narrowed(images), largestClip: largestClip ?? self.largestClip,
            disk: disk ?? self.disk)
    }

    /// The shape this build ships with.
    ///
    /// - `copied` — 8 MB and five hundred records. Five hundred clips of real text came to
    ///   under a megabyte when measured, so this is ten times the room anyone has been
    ///   observed to need, and the count is the bound that will actually be reached.
    /// - `dictation` — 4 MB and five hundred. Dictations are sentences; they are smaller
    ///   than copies, and their window comes from the user's own retention setting because
    ///   a dictation is a record of something they said and that is theirs to choose.
    /// - `images` — 32 MB of decoded thumbnails and seven days. A 68-point thumbnail is
    ///   about 18 KB, so 32 MB is roughly eighteen hundred of them, far past what a panel
    ///   shows in a sitting; the seven days is what bounds the *files*.
    ///
    /// ``ClipClass/kept`` has no entry, and that is the point of it.
    ///
    /// 44 MB claimed against a 64 MB ceiling, which leaves room to raise one tier for a
    /// build without touching the others.
    public static let standard = ClipboardBudget(
        ceiling: 64 * 1_000_000,
        copied: ClipboardTier(bytes: 8 * 1_000_000, items: 500),
        dictation: ClipboardTier(bytes: 4 * 1_000_000, items: 500),
        images: ClipboardTier(bytes: 32 * 1_000_000, items: 500, days: 7),
        largestClip: 2 * 1_000_000,
        disk: 1_000_000_000)
}
