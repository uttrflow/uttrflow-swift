// The sheet over the panel's list, ready to draw, and the presenter that words each kind.
import Foundation
public import UttrflowClipboard

/// One collection offered in the move popover, with its count so two similar names can be told apart.
public struct PanelCollectionOption: Sendable, Equatable, Identifiable {
    /// The collection's name.
    public let name: String
    /// How many clips it holds.
    public let count: Int
    /// Where the clip already is, drawn as chosen so moving it out reads as a change.
    public let isCurrent: Bool

    /// The name, which is unique.
    public var id: String { name }

    /// Builds an option.
    public init(name: String, count: Int, isCurrent: Bool) {
        self.name = name
        self.count = count
        self.isCurrent = isCurrent
    }
}

/// The sheet on top of the list, ready to draw, including whether its button can be pressed.
public struct PanelSheetPresentation: Sendable, Equatable {
    /// Which sheet this is.
    public enum Kind: Sendable, Equatable {
        case aliasing
        case moving
        case confirmingDelete
        case renamingCategory
        case deletingCategory
        case formatting
        case reindenting
    }

    /// Which sheet this is.
    public let kind: Kind
    /// The heading.
    public let title: String

    /// Whether this sheet has anything to type into, asked of the kind rather than a list of exceptions.
    public var takesTyping: Bool {
        switch kind {
        case .aliasing, .moving, .renamingCategory: true
        case .confirmingDelete, .deletingCategory, .formatting, .reindenting: false
        }
    }
    /// What the field holds, exactly as typed, never the corrected form.
    public let draft: String
    /// What the empty field says.
    public let placeholder: String
    /// The quiet note saying what will actually be saved when that differs from the screen.
    public let note: String?
    /// Names the clip that already answers to this alias, since "taken" without "by what" is a guess.
    public let conflict: String?
    /// G1 — the collections, with counts.
    public let collections: [PanelCollectionOption]
    /// The words on the primary button.
    public let confirmTitle: String
    /// Whether confirming this action permanently removes user data.
    public let isConfirmDestructive: Bool
    /// What the formatter wants to change, cut to the parts that changed; empty for every other sheet.
    public let diff: [TextDiff.Line]
    /// Whether Return would do anything; the reason it would not is in ``note`` or ``conflict``.
    public let isConfirmEnabled: Bool

    /// Builds the sheet; the diff is empty unless given.
    public init(
        kind: Kind,
        title: String,
        draft: String,
        placeholder: String,
        note: String?,
        conflict: String?,
        collections: [PanelCollectionOption],
        confirmTitle: String,
        isConfirmDestructive: Bool = false,
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
        self.isConfirmDestructive = isConfirmDestructive
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
            // An emptied field removes the alias, and the button says so rather than reading "Save".
            let isRemoval = proposal.corrected.isEmpty && clip?.alias != nil
            return PanelSheetPresentation(
                kind: .aliasing,
                title: clip?.alias == nil ? "Name this clip" : "Rename this clip",
                draft: draft,
                placeholder: "pgprod",
                note: note(for: proposal),
                conflict: !proposal.canCompareUnicodeNames
                    ? "Name comparison is unavailable"
                    : proposal.mixesScripts
                        ? "Use one writing system in a name"
                        : holder.map {
                            "“\(proposal.corrected)” already belongs to \(name(of: $0, in: snapshot))"
                        },
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
                // The reassurance, since renaming a collection looks like it might rename the clips inside.
                note: taken ? nil : "The clips keep their own names",
                conflict: taken ? "“\(renamed)” is already a collection" : nil,
                collections: [],
                confirmTitle: "Rename",
                isConfirmEnabled: !renamed.isEmpty && renamed != name && !taken)

        case .deletingCategory(let name, let keepingClips):
            let clips = snapshot.clips.filter { $0.category == name }
            let held = clips.count
            let pinned = clips.count(where: \.isPinned)
            let named = clips.count { $0.alias != nil }
            let protectsClips = pinned > 0 || named > 0
            let isReviewingProtectedDeletion =
                !keepingClips && snapshot.hasReviewedProtectedCategoryDeletion
            return PanelSheetPresentation(
                kind: .deletingCategory,
                title: isReviewingProtectedDeletion
                    ? "Delete kept clips from “\(name)”?" : "Delete “\(name)”?",
                draft: "",
                placeholder: "",
                // Never silently orphaned: the count is the whole question.
                note: held == 0
                    ? "It holds nothing."
                    : (isReviewingProtectedDeletion
                        ? "This removes \(pinned) pinned and \(named) named clips. Undo is available for 8 seconds."
                        : (keepingClips
                            ? "Its \(held) clip\(held == 1 ? "" : "s") move to Recent. Nothing is lost."
                            : (protectsClips
                                ? "Its \(held) clips include \(pinned) pinned and \(named) named."
                                : "Its \(held) clip\(held == 1 ? "" : "s") are deleted with it."))),
                conflict: keepingClips || isReviewingProtectedDeletion
                    ? nil : "Undo is available for 8 seconds.",
                collections: [],
                confirmTitle: keepingClips
                    ? "Delete collection"
                    : (isReviewingProtectedDeletion
                        ? "Delete both" : (protectsClips ? "Review deletion" : "Delete both")),
                isConfirmDestructive: !keepingClips,
                isConfirmEnabled: true)

        case .formatting(let id, let formatted):
            let original = snapshot.clip(id)?.text ?? ""
            return snapshot.formattingSheets.sheet(from: original, to: formatted)

        case .reindenting(let id, let formatted):
            let original = snapshot.clip(id)?.text ?? ""
            return snapshot.formattingSheets.sheet(
                from: original, to: formatted, title: "Re-indent this code?",
                confirmTitle: "Apply re-indent", kind: .reindenting)

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

    /// The formatting sheet for a diff computed once, or for a pair too large to compare line by line.
    static func formattingSheet(
        _ comparison: TextDiff.Comparison, changes: Bool,
        title: String = "Format this code?", confirmTitle: String = "Keep it",
        kind: PanelSheetPresentation.Kind = .formatting
    ) -> PanelSheetPresentation {
        let note: String
        let diff: [TextDiff.Line]
        let isConfirmEnabled: Bool
        switch comparison {
        case .lines(let all):
            let changed = TextDiff.changedLines(in: all)
            // The count leads, because the panel cannot show a diff of any size and the number decides.
            note = "\(changed) line\(changed == 1 ? "" : "s") would change"
            diff = TextDiff.interesting(in: all)
            isConfirmEnabled = changed > 0
        case .tooLarge(let before, let after):
            note =
                "Too large to compare line by line: \(before) line\(before == 1 ? "" : "s") before, \(after) after"
            diff = []
            isConfirmEnabled = changes
        }
        return PanelSheetPresentation(
            kind: kind,
            title: title,
            draft: "",
            placeholder: "",
            note: note,
            conflict: "This change cannot be undone",
            collections: [],
            confirmTitle: confirmTitle,
            isConfirmEnabled: isConfirmEnabled,
            diff: diff)
    }

    /// What the conflict line calls the clip holding an alias, which says nothing of a masked secret's text.
    static func name(of holder: Clip, in snapshot: PanelSnapshot) -> String {
        snapshot.isMasked(holder) ? "a hidden credential" : holder.summary
    }

    /// F4 — said only when correction actually changed something.
    static func note(for proposal: AliasProposal) -> String? {
        guard proposal.wasCorrected else { return nil }
        return "Saved as “\(proposal.corrected)”, so it matches however you type it"
    }

    /// Warns before a second collection is made under an existing name; silent when the spelling matches.
    static func existing(_ named: String, in snapshot: PanelSnapshot) -> String? {
        let match = snapshot.existingCategory(named: named)
        return match == named ? nil : match
    }

    /// Every collection with its count, marking the one the clip is in.
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

    /// Says which thing is about to be lost, which is why this clip asks when the others do not.
    static func reasonItIsKept(_ clip: Clip) -> String? {
        if let alias = clip.alias { return "It answers to “\(alias)”, which will be gone too." }
        if let category = clip.category { return "It is filed under “\(category)”." }
        if clip.isPinned { return "It is pinned." }
        return nil
    }
}
