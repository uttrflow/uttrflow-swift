// The quick panel's kind filters and collection chips.

import AppKit
import SwiftUI
import UttrflowClipboard
import UttrflowUX

extension QuickPanelView {
    // MARK: - Chips

    /// The mark at the head of the search bar, or nothing when the bundle lacks the resource.
    @ViewBuilder var logo: some View {
        if let mark = Self.logoMark {
            // The resource is an alpha shape, so the tint here is what draws it.
            Image(nsImage: mark)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.panelAccentBright)
                .frame(width: 20, height: 20)
                .accessibilityLabel("Uttrflow")
        }
    }

    /// The mark, read once, since `Bundle.image(forResource:)` does not cache and `body` runs on every key.
    private static let logoMark = Bundle.module.image(forResource: "uttrflow-logo")

    /// One scrolling row: the kind filters as a segmented control, then the collection chips.
    var chipRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    QuickPanelSegments(filters: presentation.filters) { relayKey(.filter($0)) }
                    ForEach(presentation.categories) { chip in
                        pill(
                            chip.title, category: chip.category,
                            isActive: chip.isActive, shortcut: chip.shortcut
                        ) {
                            // `chosen`, not `shortcut`: a chip past the ninth has no number.
                            relayKey(.category(number: chip.chosen))
                        }
                        .id(chip.id)
                        // On the chip, which is the thing renamed or deleted; All has no menu.
                        .contextMenu {
                            if let category = chip.category {
                                Button("Rename…") { onIntent(.renameCategory(category)) }
                                    .keyboardShortcut("r", modifiers: [.command, .shift])
                                Button("Delete…") { onIntent(.deleteCategory(category)) }
                                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.never)
            // Scrolls a collection chosen by ⌘-digit into view, so the chip agrees with the list.
            .onChange(of: activeCategory) { _, active in
                guard let active else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    proxy.scrollTo(active, anchor: .trailing)
                }
            }
        }
        .frame(height: QuickPanelMetrics.chipRowHeight)
        .padding(.bottom, 10)
    }

    /// Which collection is on, if any — the thing the row scrolls to keep in view.
    var activeCategory: String? {
        presentation.categories.first { $0.isActive }?.id
    }

    /// One collection chip, tinted when it is the one on.
    func pill(
        _ title: String, category: String?, isActive: Bool, shortcut: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                    // One line at most 160 points, so a long or multi-line name cannot stretch the row.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 160)
                if let shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.65)
                }
            }
            .foregroundStyle(isActive ? Color.panelAccentBright : Color.panelLabelSoft)
            // Nine points either side keeps eight chips within a 420-point panel.
            .padding(.horizontal, 9)
            .frame(height: 26)
            // A wash, not a fill, so the active chip stays quieter than the clip about to be pasted.
            .background(isActive ? Color.panelAccentBright.opacity(0.16) : .clear, in: .capsule)
            .overlay(
                Capsule().strokeBorder(
                    isActive ? Color.panelAccentBright.opacity(0.35) : Color.panelLine,
                    lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(shortcut.map { "Shortcut command \($0)" } ?? "")
        .onKeyPress(phases: .down) { press in
            guard let category,
                press.characters.lowercased() == "r",
                press.modifiers.contains(.command), press.modifiers.contains(.shift)
            else { return .ignored }
            onIntent(.renameCategory(category))
            return .handled
        }
        .accessibilityActions {
            if let category {
                Button("Rename collection") { onIntent(.renameCategory(category)) }
                Button("Delete collection") { onIntent(.deleteCategory(category)) }
            }
        }
    }
}
