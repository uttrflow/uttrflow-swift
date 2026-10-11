// One row of the quick panel's list, and the button style that gives it press feedback.

import AppKit
import SwiftUI
import UttrflowClipboard
import UttrflowUX

// MARK: - Menu state

enum PanelRowMenuEvent {
    case scroll
    case windowResignedKey
    case clickAway
}

struct PanelRowMenuState {
    private(set) var rowID: UUID?

    mutating func open(_ rowID: UUID?) {
        self.rowID = rowID
    }

    mutating func handle(_ event: PanelRowMenuEvent) {
        rowID = nil
    }

    mutating func select(_ action: PanelAction, perform: (PanelIntent) -> Void) {
        rowID = nil
        perform(action.intent)
    }
}

// MARK: - Row

/// Claims right-clicks and ctrl-clicks in `hitTest` and lets every other click through to the row.
struct QuickPanelRow: View, @MainActor Equatable {
    let row: PanelRow
    let isSelected: Bool
    let hasSelection: Bool
    let isMenuOpen: Bool
    let hint: String
    /// Bumped on every open, so a hover left over from the last showing is dropped.
    let openCount: Int
    let onKey: (PanelKey) -> Void
    let onAction: (PanelIntent) -> Void
    let onMenu: (UUID?) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Compares what is drawn; the callbacks are the panel's own and stable across updates.
    static func == (lhs: QuickPanelRow, rhs: QuickPanelRow) -> Bool {
        lhs.row == rhs.row && lhs.isSelected == rhs.isSelected && lhs.hasSelection == rhs.hasSelection
            && lhs.isMenuOpen == rhs.isMenuOpen && lhs.hint == rhs.hint
            && lhs.openCount == rhs.openCount
    }

    /// B6 — ⌘-click is ⌘⏎ on the row under the pointer.
    private func choose(_ row: PanelRow, plain: Bool) {
        onKey(plain ? .choosePlain(row.id) : .choose(row.id))
    }

    var body: some View {
        let look = QuickPanelRowAppearance.of(
            row, isSelected: isSelected, hovered: isHovered ? row.id : nil,
            hasSelection: hasSelection)
        return Button {
            // Reads ⌘ at the click rather than tracking it as state; a modifier is not a mode.
            choose(row, plain: NSEvent.modifierFlags.contains(.command))
        } label: {
            HStack(spacing: 9) {
                mark(row)
                if let file = row.imageFile { thumbnail(file, selected: isSelected) }
                if let alias = row.alias { aliasChip(alias) }
                ForEach(row.tags, id: \.self) { aliasChip("#" + $0) }
                if let language = row.language { languageChip(language) }
                if row.containsDisplayHazards { hiddenCharactersBadge }
                if let measurements = row.measurements {
                    Text(measurements)
                        .font(.system(size: 11.5))
                        .foregroundStyle(
                            row.isImageMissing || row.isFileMissing ? Color.panelKey : Color.panelLabelSoft
                        )
                        .lineLimit(1)
                        // Sized to content, or an empty summary takes half the row and truncates this.
                        .fixedSize(horizontal: true, vertical: false)
                }
                if let linkHost = row.linkHost, !linkHost.warnings.isEmpty { linkWarningBadge(linkHost) }
                summaryText(row)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Shows the whole line as a tooltip; whether there is one is `PanelRow.tooltip`'s answer.
                    .help(row.linkHost?.tooltip ?? row.tooltip ?? "")
                if row.additionalLineCount > 0 {
                    Text(
                        String(
                            localized: "+\(row.additionalLineCount) lines",
                            comment: "Clip row, lines after the summary")
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.panelLabelDim)
                    .fixedSize()
                    .accessibilityLabel(
                        String(
                            localized: "\(row.additionalLineCount) additional lines",
                            comment: "Clip row, lines after the summary spoken by VoiceOver")
                    )
                    .help(row.tooltip ?? "")
                }
                trailing(row, showsActions: look.showsActions)
            }
            // Tighter on the leading edge: the glyph sits in the gutter, the ⋯ wants the room on the right.
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .frame(height: QuickPanelMetrics.rowHeight)
            .background(
                look.isSelected
                    // A wash of the accent under the ring; together they mark the row without shouting.
                    ? AnyShapeStyle(Color.panelAccent.opacity(0.08))
                    : AnyShapeStyle(look.isFilled ? Color.panelLift : .clear),
                in: .rect(cornerRadius: 8)
            )
            // A faint ring, not a brighter fill, because hover fills too and only one row answers Return.
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        look.isSelected ? Color.panelAccent.opacity(0.38) : .clear,
                        lineWidth: 1)
            )
            .opacity(look.isSubdued ? 0.55 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(PressableRow())
        // In front of the row, not behind it: hit testing stops at the first view that claims the point.
        .overlay(
            RightClickWatch { onMenu(row.id) }
        )
        // `NSTrackingArea` rather than `.onHover`, which only reports while Uttrflow is the active app.
        .background(
            PointerWatch { isInside in isHovered = isInside }
        )
        .onChange(of: openCount) { isHovered = false }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: look)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuickPanelSpeech.label(for: row))
        .accessibilityHint(hint)
        .accessibilityAddTraits(look.isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityActions {
            // The same actions the pointer gets, spoken; the ⋯ button is hidden from VoiceOver.
            ForEach(row.actions) { action in
                Button(action.title) { onAction(action.intent) }
            }
        }
    }

    @ViewBuilder private func mark(_ row: PanelRow) -> some View {
        let glyph = Image(systemName: row.symbolName)
        let colour = row.kind.panelTint
        if let swatch = row.swatch {
            QuickPanelColourSwatch(colour: swatch)
        } else if QuickPanelSpeech.hasTile(row.kind) {
            glyph
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colour)
                .frame(width: 22, height: 22)
                .background(colour.opacity(0.15), in: .rect(cornerRadius: 6))
        } else {
            // Small and dim: four rows in five carry this glyph, so it must read as texture, not signal.
            glyph
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(colour.opacity(0.62))
                .frame(width: 17)
        }
    }

    /// The picture, decoded once at drawn size; a file that has gone shows the card colour.
    private func thumbnail(_ file: URL, selected: Bool) -> some View {
        // Its own view, so a decode landing redraws this picture and not the whole panel; see `PanelThumbnails`.
        PanelThumbnailView(file: file, isSelected: selected)
            .frame(width: 34, height: 24)
            .clipShape(.rect(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.panelLine, lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// Drawn only when the detector is confident, and quieter than the alias chip beside it.
    private func languageChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.panelCode)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Color.panelCode.opacity(0.12), in: .rect(cornerRadius: 5))
            .fixedSize()
            .accessibilityLabel(
                String(localized: "\(text) code", comment: "Clip row, detected code language"))
    }

    /// A link row's host in strong weight, ahead of the address it came from.
    @ViewBuilder private func summaryText(_ row: PanelRow) -> some View {
        let size: CGFloat = row.isMasked ? 12 : 12.5
        let design: Font.Design = row.isMonospaced && !row.isMasked ? .monospaced : .default
        if let linkHost = row.linkHost {
            HStack(spacing: 0) {
                Text(linkHost.host)
                    .font(.system(size: size, weight: .semibold, design: design))
                    .foregroundStyle(Color.panelLabel)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text("  \(row.summary)")
                    .font(.system(size: size, design: design))
                    .foregroundStyle(Color.panelLabelDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            Text(row.summary)
                .font(.system(size: size, design: design))
                .foregroundStyle(row.isMasked ? Color.panelLabelDim : Color.panelLabel)
        }
    }

    private func linkWarningBadge(_ linkHost: LinkHostDisplay) -> some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.panelDestructive)
            .help(linkHost.warnings.joined(separator: "\n"))
            .accessibilityHidden(true)
    }

    private var hiddenCharactersBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(String(localized: "Hidden chars", comment: "Clip row, hidden character warning badge"))
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.panelDestructive)
        .padding(.horizontal, 5)
        .frame(height: 18)
        .background(Color.panelDestructive.opacity(0.12), in: .rect(cornerRadius: 5))
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func aliasChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.panelKey)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Color.panelKey.opacity(0.14), in: .rect(cornerRadius: 6))
            .fixedSize()
    }

    /// The pin and the ⋯, anchored outside any hover swap so the far right of a row never moves.
    @ViewBuilder private func trailing(_ row: PanelRow, showsActions: Bool) -> some View {
        HStack(spacing: 6) {
            // Only state that belongs to this clip: a pin. Time and actions live in the ⋯ menu.
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.panelAccentBright)
            }
            Button {
                onMenu(isMenuOpen ? nil : row.id)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    // Ghost grey at rest, ordinary grey on the row being looked at: findable, not noticeable.
                    .foregroundStyle(colourOfDots(for: row, showsActions: showsActions))
                    .frame(width: 20, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The row already speaks every action through its accessibility actions.
            .accessibilityHidden(true)
        }
        .fixedSize()
    }

    private func colourOfDots(for row: PanelRow, showsActions: Bool) -> Color {
        if isMenuOpen { return .panelAccentBright }
        if showsActions || isSelected { return .panelLabelSoft }
        return .panelGhost
    }

}

// MARK: - Styles

/// Darkens the row while the mouse is down; the click's only other feedback is the panel vanishing.
struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.06), value: configuration.isPressed)
    }
}

extension ClipKind {
    /// The colour a clip of this kind is drawn in, shared by every part of the panel.
    var panelTint: Color {
        switch self {
        case .link: .panelLink
        case .code: .panelCode
        case .secret: .panelKey
        case .text, .colour, .image, .filePath, .file: .panelLabelDim
        }
    }
}
