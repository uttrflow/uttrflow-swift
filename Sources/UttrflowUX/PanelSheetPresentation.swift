import Foundation
public import UttrflowClipboard

/// One collection offered in the move popover, and how full it is.
///
/// The count is there because two collections told apart by nothing is how a clip ends up
/// in the wrong one; a collection holding forty clips and one holding none are obviously
/// different things even when their names are similar.
public struct PanelCollectionOption: Sendable, Equatable, Identifiable {
    public let name: String
    public let count: Int
    /// Where the clip already is, drawn as chosen so that moving it out of a collection
    /// reads as a change rather than as a fresh choice.
    public let isCurrent: Bool

    public var id: String { name }

    public init(name: String, count: Int, isCurrent: Bool) {
        self.name = name
        self.count = count
        self.isCurrent = isCurrent
    }
}

/// The sheet on top of the list, ready to draw.
///
/// Every word decided here, like the rest of the panel — including whether the primary
/// button can be pressed. That is the thing a view most often decides for itself and gets
/// subtly out of step with what Return does, and a button that is enabled when Return does
/// nothing is a button that looks broken.
public struct PanelSheetPresentation: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case aliasing
        case moving
        case confirmingDelete
        case renamingCategory
        case deletingCategory
        case formatting
    }

    public let kind: Kind
    public let title: String

    /// Whether this sheet has anything to type into.
    ///
    /// Decided here rather than in the view, which used to draw the field for every kind
    /// except the delete confirmation. That was a list of one, and it went out of date the
    /// moment a second typing-free sheet arrived: the formatting sheet came up with an
    /// empty box above its diff, focused and inviting, with nothing it could accept. Ask
    /// what a sheet is instead of naming the exceptions.
    public var takesTyping: Bool {
        switch kind {
        case .aliasing, .moving, .renamingCategory: true
        case .confirmingDelete, .deletingCategory, .formatting: false
        }
    }
    /// What the field holds, exactly as typed. Never the corrected form: a field that
    /// rewrites characters as they are typed is a field nobody can type in.
    public let draft: String
    public let placeholder: String
    /// F4 — the quiet note. Says what will actually be saved when that differs from what
    /// is on screen. Not an error; the alias is still accepted.
    public let note: String?
    /// F3 — names the clip that already answers to this alias, because "taken" without
    /// "by what" leaves the user guessing at something they cannot see.
    public let conflict: String?
    /// G1 — the collections, with counts.
    public let collections: [PanelCollectionOption]
    public let confirmTitle: String
    /// D6 — what the formatter wants to change, cut down to the parts that changed.
    /// Empty for every other sheet.
    public let diff: [TextDiff.Line]
    /// F5 — whether Return would do anything. The reason it would not is in ``note`` or
    /// ``conflict``, on screen rather than hidden in a disabled button's tooltip.
    public let isConfirmEnabled: Bool

    public init(
        kind: Kind,
        title: String,
        draft: String,
        placeholder: String,
        note: String?,
        conflict: String?,
        collections: [PanelCollectionOption],
        confirmTitle: String,
        isConfirmEnabled: Bool,
        diff: [TextDiff.Line] = []
    ) {
        self.kind = kind
        self.title = title
        self.draft = draft
        self.placeholder = placeholder
        self.note = note
        self.conflict = conflict
        self.collections = collections
        self.confirmTitle = confirmTitle
        self.isConfirmEnabled = isConfirmEnabled
        self.diff = diff
    }
}

extension PanelPresenter {
    /// Draws whatever sheet is open, or nothing.
    static func sheet(for snapshot: PanelSnapshot) -> PanelSheetPresentation? {
        guard let sheet = snapshot.sheet else { return nil }
        let clip = sheet.clip.flatMap(snapshot.clip)

        switch sheet {
        case .aliasing(let id, let draft):
            let proposal = PanelAlias.propose(
                draft, for: id, among: snapshot.clips, locale: snapshot.locale)
            let holder = proposal.takenBy.flatMap(snapshot.clip)
            // An emptied field removes the alias, and the button says so rather than
            // reading "Save" over an action that takes something away.
            let isRemoval = proposal.corrected.isEmpty && clip?.alias != nil
            return PanelSheetPresentation(
                kind: .aliasing,
                title: clip?.alias == nil ? "Name this clip" : "Rename this clip",
                draft: draft,
                placeholder: "pgprod",
                note: note(for: proposal),
                conflict: holder.map { "“\(proposal.corrected)” already belongs to \($0.summary)" },
                collections: [],
                confirmTitle: isRemoval ? "Remove name" : "Save",
                isConfirmEnabled: proposal.isUsable || isRemoval)

        case .moving(let id, let draft):
            let named = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return PanelSheetPresentation(
                kind: .moving,
                title: "Move to a collection",
                draft: draft,
                placeholder: "New collection…",
                note: existing(named, in: snapshot).map {
                    "Files it into “\($0)”, which already exists"
                },
                conflict: nil,
                collections: collections(of: snapshot, for: id),
                confirmTitle: "Move",
                isConfirmEnabled: !named.isEmpty)

        case .renamingCategory(let name, let draft):
            let renamed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let taken = snapshot.existingCategory(named: renamed, besides: name) != nil
            return PanelSheetPresentation(
                kind: .renamingCategory,
                title: "Rename “\(name)”",
                draft: draft,
                placeholder: name,
                // G5 — the reassurance, because renaming a collection looks like the kind
                // of thing that might take the names inside it with it.
                note: taken ? nil : "The clips keep their own names",
                conflict: taken ? "“\(renamed)” is already a collection" : nil,
                collections: [],
                confirmTitle: "Rename",
                isConfirmEnabled: !renamed.isEmpty && renamed != name && !taken)

        case .deletingCategory(let name, let keepingClips):
            let held = snapshot.clips.count { $0.category == name }
            return PanelSheetPresentation(
                kind: .deletingCategory,
                title: "Delete “\(name)”?",
                draft: "",
                placeholder: "",
                // G6 — never silently orphaned. The count is the whole question: deleting
                // an empty collection and deleting one holding forty clips are different
                // acts, and only one of them needs thinking about.
                note: held == 0
                    ? "It holds nothing."
                    : (keepingClips
                        ? "Its \(held) clip\(held == 1 ? "" : "s") move to Recent. Nothing is lost."
                        : "Its \(held) clip\(held == 1 ? "" : "s") are deleted with it."),
                conflict: keepingClips ? nil : "This cannot be undone",
                collections: [],
                confirmTitle: keepingClips ? "Delete collection" : "Delete both",
                isConfirmEnabled: true)

        case .formatting(let id, let formatted):
            let original = snapshot.clip(id)?.text ?? ""
            let changed = TextDiff.changedLines(from: original, to: formatted)
            return PanelSheetPresentation(
                kind: .formatting,
                title: "Format this code?",
                draft: "",
                placeholder: "",
                // D6 — the count leads, because a 420-point panel cannot show a diff of
                // any size honestly and the number is what a person decides on.
                note: "\(changed) line\(changed == 1 ? "" : "s") would change",
                conflict: nil,
                collections: [],
                confirmTitle: "Keep it",
                isConfirmEnabled: changed > 0,
                diff: TextDiff.interesting(from: original, to: formatted))

        case .confirmingDelete:
            return PanelSheetPresentation(
                kind: .confirmingDelete,
                title: "Delete this clip?",
                draft: "",
                placeholder: "",
                note: clip.flatMap(reasonItIsKept),
                conflict: nil,
                collections: [],
                confirmTitle: "Delete",
                isConfirmEnabled: true)
        }
    }

    /// F4 — said only when correction actually changed something.
    static func note(for proposal: AliasProposal) -> String? {
        guard proposal.wasCorrected else { return nil }
        return "Saved as “\(proposal.corrected)”, so it matches however you type it"
    }

    /// G3 — warns before a second collection is made under a name that already exists,
    /// rather than after, when there are two chips reading the same word.
    ///
    /// Silent when the spelling matches exactly: that is simply choosing the collection.
    static func existing(_ named: String, in snapshot: PanelSnapshot) -> String? {
        let match = snapshot.existingCategory(named: named)
        return match == named ? nil : match
    }

    static func collections(
        of snapshot: PanelSnapshot, for id: Clip.ID
    )
        -> [PanelCollectionOption]
    {
        let current = snapshot.clip(id)?.category
        return snapshot.categories.map { name in
            PanelCollectionOption(
                name: name,
                count: snapshot.clips.count { $0.category == name },
                isCurrent: name == current)
        }
    }

    /// F8 — says which thing is about to be lost, because that is the answer to "why is
    /// this one asking me when the others did not".
    static func reasonItIsKept(_ clip: Clip) -> String? {
        if let alias = clip.alias { return "It answers to “\(alias)”, which will be gone too." }
        if let category = clip.category { return "It is filed under “\(category)”." }
        if clip.isPinned { return "It is pinned." }
        return nil
    }
}
