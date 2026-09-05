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
    }

    /// Which sheet this is.
    public let kind: Kind
    /// The heading.
    public let title: String

    /// Whether this sheet has anything to type into, asked of the kind rather than a list of exceptions.
    public var takesTyping: Bool {
        switch kind {
        case .aliasing, .moving, .renamingCategory: true
        case .confirmingDelete, .deletingCategory, .formatting: false
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
            // An emptied field removes the alias, and the button says so rather than reading "Save".
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
                // The reassurance, since renaming a collection looks like it might rename the clips inside.
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
                // Never silently orphaned: the count is the whole question.
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
                // The count leads, because the panel cannot show a diff of any size and the number decides.
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
