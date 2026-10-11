// The redesigned pages' shared parts: the title bar, buttons, cards, chips and editor fields.

import UttrflowUX
import SwiftUI

/// The redesigned pages' measures, in one place so the pages agree.
enum PageMetrics {
    /// The margin either side of a redesigned page.
    static let margin: CGFloat = 34
    /// A card's corner.
    static let cardRadius: CGFloat = 16
    /// The gap between table columns.
    static let columnSpacing: CGFloat = 12
    /// A table row's inset from the card's edge.
    static let rowInset: CGFloat = 16
}

/// The redesigned band a page opens with: the title, the search field and the page's button, then the caption.
struct PageTitleBar: View {
    let chrome: MainPageChrome
    @Binding var query: String
    /// Rises when Find is chosen; handed on to the search field, which is what takes the focus.
    var searchFocusRequest = 0
    var onIntent: (MainIntent) -> Void
    var onSearch: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Text(chrome.title)
                    .font(BrandFont.display(size: 28, weight: .semibold))
                    .tracking(-0.84)
                    .foregroundStyle(PagePalette.text)
                    .fixedSize()
                    .accessibilityAddTraits(.isHeader)
                if let search = chrome.search {
                    PageSearchField(
                        field: search, query: $query, focusRequest: searchFocusRequest,
                        onSearch: onSearch)
                } else {
                    Spacer(minLength: 0)
                }
                if let sort = chrome.sort {
                    PageSortMenu(sort: sort, onIntent: onIntent)
                }
                if let add = chrome.addAction {
                    PageButton(action: add, isProminent: true, onIntent: onIntent)
                }
            }
            .frame(height: 38)
            if let caption = chrome.caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(PagePalette.faint)
            }
        }
        .padding(.horizontal, PageMetrics.margin)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The wide search field in the title bar, which reports what was typed and decides nothing.
struct PageSearchField: View {
    let field: MainSearchField
    @Binding var query: String
    /// Rises when Find is chosen, which is the one thing that moves the caret here without a click.
    var focusRequest = 0
    var onSearch: (String) -> Void

    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.faint)
            TextField(field.placeholder, text: $query, selection: $selection)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(PagePalette.text)
                .focused($isFocused)
                .onChange(of: query) { _, new in onSearch(new) }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(PagePalette.text.opacity(0.05), in: .rect(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(PagePalette.text.opacity(0.1), lineWidth: 1)
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        // Selected as well as focused, so the next keystroke replaces the old query rather than extending it.
        .onChange(of: focusRequest) { _, _ in
            isFocused = true
            selection = TextSelection(range: query.startIndex..<query.endIndex)
        }
        // Escape empties a field with something in it, and is left alone when there is nothing to clear.
        .onKeyPress(.escape) {
            guard !query.isEmpty else { return .ignored }
            query = ""
            onSearch("")
            return .handled
        }
    }
}

/// A page button: the solid one that does the page's main thing, or a quiet outlined one.
struct PageButton: View {
    let action: MainAction
    var isProminent = false
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Button {
            onIntent(action.intent)
        } label: {
            HStack(spacing: 6) {
                if let symbol = action.symbolName {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                }
                Text(action.title)
            }
        }
        .buttonStyle(PageButtonStyle(isProminent: isProminent))
    }
}

/// The redesign's button: ink on a solid pill when prominent, a faint outlined film otherwise.
struct PageButtonStyle: ButtonStyle {
    var isProminent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: isProminent ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(isProminent ? Color.redesignWindow : PagePalette.text)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                isProminent ? PagePalette.text : PagePalette.text.opacity(0.08),
                in: .rect(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(PagePalette.text.opacity(0.14), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(.rect)
    }
}

extension View {
    /// The redesign's card: a faint film with a hairline rim, edged in an accent when given one.
    func pageCard(edge: Color? = nil) -> some View {
        background(
            PagePalette.text.opacity(0.045),
            in: .rect(cornerRadius: PageMetrics.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: PageMetrics.cardRadius, style: .continuous)
                .strokeBorder(edge ?? PagePalette.text.opacity(0.08), lineWidth: 1)
        }
    }
}

/// A small capitalised label over a section.
struct PageSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.84)
            .foregroundStyle(PagePalette.faint)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One filter pill; the selected one is solid.
struct PageFilterChip: View {
    let option: MainScopeOption
    var onSelect: (String) -> Void

    var body: some View {
        Button {
            onSelect(option.id)
        } label: {
            Text(option.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(option.isSelected ? Color.redesignWindow : PagePalette.text.opacity(0.7))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    option.isSelected ? PagePalette.text : PagePalette.text.opacity(0.06), in: .capsule
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }
}

/// A tinted label with a dot, such as where a word came from.
struct PageTintChip: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: .capsule)
        .fixedSize()
    }
}

/// The small capitalised badge on an editor card: "NEW", "EDITING".
struct PageBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(PagePalette.badgeInk)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(PagePalette.dictation.opacity(0.16), in: .rect(cornerRadius: 5))
    }
}

/// One labelled field on an editor card, sunk into its well.
struct PageEditorField<Field: View>: View {
    let label: String
    let symbolName: String
    let tint: Color
    @ViewBuilder var field: () -> Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                // The field below carries this text as its name, so VoiceOver reads it once.
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(PagePalette.text.opacity(0.6))
                    .accessibilityHidden(true)
            }
            field()
                .accessibilityLabel(label)
                .font(.system(size: 13.5))
                .foregroundStyle(PagePalette.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PagePalette.fieldWell, in: .rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(PagePalette.text.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

/// A quiet icon button at the end of a table row, which stays reachable by VoiceOver while its glyph is hidden.
struct PageRowIconButton: View {
    let action: MainAction
    /// Whether the glyph is drawn; the button itself is never hidden, since SwiftUI drops a transparent view from VoiceOver.
    var isShown = true
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Button {
            onIntent(action.intent)
        } label: {
            Image(systemName: action.symbolName ?? "questionmark")
                .font(.system(size: 12))
                .foregroundStyle(action.isDestructive ? Color.criticalInk : PagePalette.text.opacity(0.5))
                .opacity(isShown ? 1 : 0)
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

/// An editor card's last line: why it cannot be saved, then Cancel and Save.
struct PageEditorFooter: View {
    let problem: String?
    let cancel: MainAction
    let save: MainAction
    let canSave: Bool
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let problem {
                Text(problem)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.warningInk)
            }
            Spacer(minLength: 0)
            PageButton(action: cancel, onIntent: onIntent)
            PageButton(action: save, isProminent: true, onIntent: onIntent)
                .disabled(!canSave)
        }
    }
}

extension PagePalette {
    /// A quiet chip's grey.
    static let neutral = Color(nsColor: .orbit(BrandPalette.Redesign.neutralAccent))
    /// A "New" badge's ink.
    static let badgeInk = Color(nsColor: .orbit(BrandPalette.Redesign.badgeInk))
    /// An editor field's well.
    static let fieldWell = Color(nsColor: .orbit(BrandPalette.Redesign.fieldWell))
}

/// The menu choosing the order a page's list is read in; VoiceOver hears the order in force.
struct PageSortMenu: View {
    let sort: MainScope
    var onIntent: (MainIntent) -> Void

    var body: some View {
        Picker(sort.title, selection: selection) {
            ForEach(sort.options) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(sort.title)
    }

    /// Reads the order from the presentation and reports a change back as an intent.
    private var selection: Binding<String> {
        Binding(
            get: { sort.options.first(where: \.isSelected)?.id ?? "" },
            set: { onIntent(.sort($0)) })
    }
}
