// The quick panel's sheet overlay: its questions, diffs and collection lists.

import AppKit
import SwiftUI
import UttrflowClipboard
import UttrflowUX

extension QuickPanelView {
    /// The question on top of the list, dimming but not hiding the row it is about.
    @ViewBuilder
    func sheetOverlay(_ sheet: PanelSheetPresentation) -> some View {
        ZStack {
            // Catches the click that would otherwise land on a row, and means what esc means.
            Color.black.opacity(0.45)
                .clipShape(.rect(cornerRadius: QuickPanelMetrics.corner))
                .contentShape(.rect)
                .onTapGesture { relayKey(.escape) }

            VStack(alignment: .leading, spacing: 12) {
                Text(sheet.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelLabel)
                    .accessibilityAddTraits(.isHeader)

                if sheet.takesTyping {
                    sheetField(sheet)
                }
                if !sheet.collections.isEmpty {
                    collectionList(sheet)
                }
                if !sheet.diff.isEmpty { diffView(sheet.diff) }
                if let conflict = sheet.conflict {
                    sheetNote(conflict, tint: Color.panelKey)
                }
                if let note = sheet.note {
                    sheetNote(note, tint: Color.panelLabelDim)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button(String(localized: "Cancel", comment: "Quick panel sheet, dismiss action")) {
                        relayKey(.escape)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.panelLabelSoft)
                    Button(sheet.confirmTitle) { relayKey(.return) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            sheet.isConfirmDestructive ? Color.white : Color.panelAccentText
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                sheet.isConfirmEnabled
                                    ? (sheet.isConfirmDestructive
                                        ? Color.panelDestructive : Color.panelAccent)
                                    : Color.panelLine)
                        )
                        .disabled(!sheet.isConfirmEnabled)
                }
            }
            .padding(16)
            // A cap, not a width, so the sheet shrinks with a panel narrower than the design.
            .frame(maxWidth: QuickPanelMetrics.width - 56, alignment: .leading)
            .panelPopover(cornerRadius: 12, shadowOpacity: 0.4, radius: 24, y: 8)
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Bound to the presentation, not `@State`, so the field cannot disagree with its conflict note.
    func sheetField(_ sheet: PanelSheetPresentation) -> some View {
        // Edit grows with a clip's lines, and ⏎ still saves; ⌥⏎ starts a new line, as in any text field.
        TextField(
            sheet.placeholder,
            // Taking focus writes the unchanged text back, which is no edit and is not relayed.
            text: Binding(get: { sheet.draft }, set: { if $0 != sheet.draft { relayKey(.draft($0)) } }),
            axis: sheet.kind == .editing ? .vertical : .horizontal
        )
        .lineLimit(sheet.kind == .editing ? 8 : 1)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Color.panelLabel)
        .focused($isSheetFocused)
        .onKeyPress(.escape) { send(.escape) }
        // Both writes, in this order, in one update; see Docs/app-quick-panel.md on focus.
        .onAppear {
            isSearchFocused = false
            // On the next turn: a focus request made during `onAppear` is dropped silently.
            Task { isSheetFocused = true }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.panelWell)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(Color.panelAccent, lineWidth: 1)
        )
        .onSubmit { relayKey(.return) }
    }

    /// What the formatter wants to change, signed as well as coloured for colour-blind readers.
    private func diffView(_ lines: [TextDiff.Line]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Text(sign(for: line.kind))
                            .frame(width: 8, alignment: .leading)
                        Text(line.text.isEmpty ? " " : line.text)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(colour(for: line.kind))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(background(for: line.kind))
                }
            }
        }
        .frame(maxHeight: 150)
        .background(Color.panelWell, in: .rect(cornerRadius: 6))
    }

    private func sign(for kind: TextDiff.Kind) -> String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .same: " "
        }
    }

    private func colour(for kind: TextDiff.Kind) -> Color {
        switch kind {
        case .added: .panelAccentBright
        case .removed: .panelKey
        case .same: .panelLabelDim
        }
    }

    private func background(for kind: TextDiff.Kind) -> Color {
        switch kind {
        case .added: Color.panelAccent.opacity(0.12)
        case .removed: Color.panelKey.opacity(0.10)
        case .same: .clear
        }
    }

    /// G1 — the collections that exist, with how full each one is.
    private func collectionList(_ sheet: PanelSheetPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sheet.collections) { option in
                Button {
                    relayKey(.draft(option.name))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: option.isCurrent ? "folder.fill" : "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(
                                option.isCurrent ? Color.panelAccentBright : Color.panelLabelDim)
                        Text(option.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.panelLabel)
                        Spacer()
                        Text(verbatim: "\(option.count)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.panelLabelDim)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(
                    option.name == sheet.draft
                        ? Color.panelLift : Color.clear,
                    in: .rect(cornerRadius: 6))
            }
        }
        .frame(maxHeight: 132)
    }

    private func sheetNote(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The rule between the panel's bands.
    var hairline: some View {
        Rectangle().fill(Color.panelLine).frame(height: 1)
    }
}
