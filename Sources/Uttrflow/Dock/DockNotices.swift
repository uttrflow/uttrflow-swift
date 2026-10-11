// The finished-state forms of the dock: badge, quiet outcome, clipboard, pill and the wide blocked notice.

import AppKit
import UttrflowCore
import UttrflowPipeline
import UttrflowUX
import SwiftUI

extension DockView {
    /// Finished: a 26-point disc for an insertion, a small pill with words for the quiet outcomes and short failures, and the wide form for the rest.
    @ViewBuilder
    func notice(_ presentation: DockPresentation, primaryLine: String) -> some View {
        switch presentation.symbolName {
        case "checkmark":
            badgeForm { InsertedMark() }
        case "waveform.slash":
            quietNotice(DockWording.restingWords(for: presentation) ?? primaryLine)
        case "doc.on.clipboard":
            clipboardNotice(presentation)
        default:
            if let line = DockWording.pillLine(for: presentation) {
                pill(presentation, line: line, primaryLine: primaryLine)
            } else {
                blocked(presentation, primaryLine: primaryLine)
            }
        }
    }

    /// Nothing heard, or too little: the struck level with the sentence that says so, readable at rest.
    func quietNotice(_ words: String) -> some View {
        HStack(spacing: 8) {
            StruckLevel()
            Text(words)
                .font(.system(size: DockMetrics.footnoteSize + 1))
                .opacity(noticeAppearance.textOpacity(normal: 0.72))
                .lineLimit(2)
                .frame(maxWidth: DockMetrics.quietTextMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minHeight: DockMetrics.clipboardHeight)
        .glass(
            cornerRadius: DockMetrics.clipboardHeight / 2,
            opaque: noticeAppearance.usesOpaqueGlass
        )
        .padding(DockMetrics.gripHitPadding)
    }

    /// The 26-point disc an insertion is drawn in.
    func badgeForm(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: DockMetrics.badgeSize, height: DockMetrics.badgeSize)
            .glass(cornerRadius: DockMetrics.badgeSize / 2)
            .padding(DockMetrics.gripHitPadding)
    }

    /// Copied rather than typed: ⌘V and the words saying so at rest, the blocked form with its fix under the pointer.
    @ViewBuilder
    func clipboardNotice(_ presentation: DockPresentation) -> some View {
        if model.isHovering, presentation.action != nil {
            pill(
                presentation, line: DockWording.blockedLine, primaryLine: presentation.primaryLine ?? "",
                symbolName: "exclamationmark.triangle", width: DockMetrics.blockedWidth)
        } else {
            HStack(spacing: 8) {
                keycap("⌘V")
                    .foregroundStyle(Color.dockWarningInk)
                if let words = DockWording.restingWords(for: presentation) {
                    Text(words)
                        .font(.system(size: DockMetrics.footnoteSize + 1))
                        .opacity(noticeAppearance.textOpacity(normal: 0.72))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 9)
            .frame(height: DockMetrics.clipboardHeight)
            .glass(
                cornerRadius: DockMetrics.clipboardHeight / 2,
                opaque: noticeAppearance.usesOpaqueGlass
            )
            .padding(DockMetrics.gripHitPadding)
        }
    }

    /// The one state with something for the reader to do, and the only wide form; the message wraps rather than truncates.
    func blocked(_ presentation: DockPresentation, primaryLine: String) -> some View {
        HStack(spacing: DockMetrics.noticeSpacing) {
            Badge(symbolName: presentation.symbolName, tint: .dockWarningFill)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.system(size: DockMetrics.bodySize, weight: .medium))
                    .lineLimit(DockMetrics.noticeMaxLines)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = presentation.secondaryLine {
                    Text(secondary)
                        .font(.system(size: DockMetrics.footnoteSize))
                        .opacity(noticeAppearance.textOpacity(normal: 0.58))
                        .lineLimit(1)
                }
                // Under the words, so the button never takes width the message needs.
                if let action = presentation.action {
                    Button(DockWording.title(for: action)) { onRecovery(action) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DockMetrics.noticeHorizontalPadding)
        .padding(.vertical, DockMetrics.noticeVerticalPadding)
        .frame(width: DockMetrics.noticeMaxWidth)
        .frame(minHeight: DockMetrics.noticeHeight)
        .glass(
            cornerRadius: DockMetrics.noticeHeight / 2,
            opaque: noticeAppearance.usesOpaqueGlass
        )
        .help(DockWording.hoverText(for: presentation, primaryLine: primaryLine))
        .padding(DockMetrics.gripHitPadding)
    }

    /// A failure with a short name: the warning disc, the line and a trailing Fix, with the full sentence on hover.
    func pill(
        _ presentation: DockPresentation, line: String, primaryLine: String, symbolName: String? = nil,
        width: CGFloat? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName ?? presentation.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dockSetupWarning)
                .frame(width: DockMetrics.noticeBadgeSize, height: DockMetrics.noticeBadgeSize)
                .background(Color.dockSetupWarning.opacity(0.2), in: .circle)
            Text(line)
                .font(.system(size: DockSetupMetrics.warningTextSize))
                .fixedSize(horizontal: width == nil, vertical: true)
                .frame(maxWidth: width == nil ? nil : .infinity, alignment: .leading)
            if let action = presentation.action {
                Button {
                    onRecovery(action)
                } label: {
                    Text(
                        String(
                            localized: "Fix", comment: "Dock failure pill, button that starts the recovery")
                    )
                    .font(.system(size: DockSetupMetrics.warningTextSize))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.14), in: .rect(cornerRadius: 6))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: width)
        .glass(
            cornerRadius: DockSetupMetrics.warningRadius,
            opaque: noticeAppearance.usesOpaqueGlass
        )
        .help(DockWording.hoverText(for: presentation, primaryLine: primaryLine))
        .padding(DockMetrics.gripHitPadding)
    }
}
