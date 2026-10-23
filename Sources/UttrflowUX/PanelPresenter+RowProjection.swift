// Projects one clipboard match into a panel row. See `Docs/panel.md`.
import Foundation
import UttrflowClipboard

extension PanelPresenter {
    // MARK: - A row

    static func row(
        for result: PanelResult, in snapshot: PanelSnapshot, isSelected: Bool
    ) -> PanelRow {
        let clip = result.clip
        let isMasked = clip.kind == .secret && !snapshot.revealed.contains(clip.id)
        let isGone = clip.image != nil && snapshot.missingImages.contains(clip.id)
        // H5 — never on a masked clip, or the excerpt prints the secret. See `Docs/panel.md`.
        let excerpt =
            isMasked || result.match != .content
            ? nil
            : self.excerpt(of: clip.text, around: snapshot.needle, locale: snapshot.locale)
        // The same words the history page uses, or "just now" means two things.
        let when = HistoryPresenter.when(
            clip.copiedAt, relativeTo: snapshot.now, locale: snapshot.locale)
        return PanelRow(
            id: clip.id,
            summary: isMasked ? mask : ClipTextSafety.escaped(excerpt ?? clip.summary),
            additionalLineCount: isMasked ? 0 : clip.additionalLineCount,
            preview: isMasked ? mask : ClipTextSafety.escaped(clip.preview),
            kind: clip.kind,
            swatch: !isMasked && clip.kind == .colour
                ? ClipKindDetector.colour(in: clip.text)
                : nil,
            symbolName: symbolName(for: clip.kind),
            when: when,
            detail: detail(of: clip, when: when),
            alias: clip.alias,
            tags: clip.tags,
            category: PanelSnapshot.name(clip.category),
            isPinned: clip.isPinned,
            isMasked: isMasked,
            isSelected: isSelected,
            matched: result.match,
            measurements: isMasked ? nil : measurements(of: clip, in: snapshot),
            checklist: isMasked ? nil : checklistProgress(of: clip, in: snapshot),
            imageFile: isGone
                ? nil
                : clip.image.flatMap { image in
                    snapshot.imagesFolder?.appending(path: image.file, directoryHint: .notDirectory)
                },
            isImageMissing: isGone,
            fileNames: clip.files?.map(\.name) ?? [],
            isFileMissing: snapshot.missingFiles[clip.id] != nil,
            // Never on a masked row, which says as little as possible until asked.
            language: isMasked ? nil : clip.language?.chip,
            isMonospaced: isMonospaced(clip.kind),
            containsDisplayHazards: ClipTextSafety.containsDisplayHazards(clip.text),
            linkHost: isMasked || clip.kind != .link ? nil : LinkHostDisplay.parse(clip.text),
            actions: actions(for: clip, isMasked: isMasked, in: snapshot)
        )
    }

    /// One symbol per kind, so a row is told apart before it is read.
    static func symbolName(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .secret: "key"
        case .colour: "paintpalette"
        case .filePath: "folder"
        case .image: "photo"
        case .file: "doc.on.doc"
        }
    }

    /// What a picture or formatted-text row says, or why a picture cannot. See `Docs/panel.md`.
    static func measurements(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        if clip.files != nil {
            return snapshot.missingFiles[clip.id].map { PanelNotice.filesMissing($0).message }
        }
        guard let image = clip.image else {
            guard clip.richText != nil else { return nil }
            return MainFormatting.count(clip.text.count, "character", "characters")
        }
        if snapshot.missingImages.contains(clip.id) {
            return "The picture is no longer on this Mac"
        }
        let weight = fileSize(image.bytes)
        guard let from = clip.source?.trimmingCharacters(in: .whitespaces), !from.isEmpty else {
            return "\(image.dimensions) · \(weight)"
        }
        return "\(from) · \(weight)"
    }

    /// How many checklist boxes are checked, without copying any note text into the row.
    static func checklistProgress(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        guard let progress = PanelCache.current.checklistProgresses.progress(of: clip) else { return nil }
        return "\(progress.done) of \(progress.total)"
    }

    /// Round numbers, because nobody reads a screenshot's size to the byte.
    static func fileSize(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return "\(bytes / 1_000_000) MB" }
        if bytes >= 1_000 { return "\(bytes / 1_000) KB" }
        return "\(bytes) bytes"
    }
}
