// The Dictionary page: today's fixes, the filter chips, the words table and its editor card.

import UttrflowUX
import SwiftUI

/// The words Uttrflow knows and a general model does not.
struct DictionaryPageView: View {
    let presentation: DictionaryPresentation
    /// What is being typed into the editor, held by the window so it survives a redraw.
    @Binding var draft: DictionaryDraft
    var onIntent: (MainIntent) -> Void
    /// Reports the chosen filter chip.
    var onFilter: (String) -> Void = { _ in }

    /// The artboard's columns: word, sound, source, recogniser prompt, used, undone, and the row's controls.
    static let widths: [PageColumnWidth] = [
        .share(1.1), .share(1.1), .share(1), .share(1), .fixed(55), .fixed(60), .fixed(76),
    ]

    var body: some View {
        if let empty = presentation.emptyState, presentation.filters.isEmpty,
            presentation.notLearning == nil
        {
            MainEmptyStateView(state: empty, onIntent: onIntent)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let editor = presentation.editor {
                        DictionaryEditorView(editor: editor, draft: $draft, onIntent: onIntent)
                            .padding(.bottom, 14)
                    }
                    if let label = presentation.fixesLabel {
                        DictionaryFixesView(
                            label: label, fixes: presentation.fixes, onIntent: onIntent
                        )
                        .padding(.bottom, 18)
                    }
                    if !presentation.filters.isEmpty {
                        filters.padding(.bottom, 14)
                    }
                    if let empty = presentation.emptyState {
                        MainEmptyStateView(state: empty, onIntent: onIntent)
                            .frame(minHeight: 220)
                    } else {
                        table
                    }
                    if let footnote = presentation.footnote {
                        MainFootnote(text: footnote)
                    }
                    if let notLearning = presentation.notLearning {
                        DictionaryNotLearningView(section: notLearning, onIntent: onIntent)
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            ForEach(presentation.filters) { PageFilterChip(option: $0, onSelect: onFilter) }
        }
    }

    private var table: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            PageTableHeader(
                titles: ["Write it as", "Say it like", "From", "Recogniser", "Used", "Undone", ""],
                widths: Self.widths)
            ForEach(presentation.rows) { row in
                PageDivider()
                DictionaryRowView(row: row, onIntent: onIntent)
            }
        }
        .pageCard()
    }
}

/// One word; a retired row is dimmed and offers Restore, and Delete waits for the pointer.
struct DictionaryRowView: View {
    let row: DictionaryRow
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false
    @FocusState private var focusedControl: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            columns
            if let trial = row.trial {
                DictionaryTrialView(line: trial, onIntent: onIntent)
                    .padding(.horizontal, PageMetrics.rowInset)
                    .padding(.bottom, 10)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var columns: some View {
        PageColumns(widths: DictionaryPageView.widths) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.word)
                    .fontWeight(.semibold)
                    .foregroundStyle(PagePalette.text)
                    .lineLimit(1)
                if let soundsLike = row.soundsLike {
                    PageTintChip(text: soundsLike, tint: PagePalette.clipboardInk)
                }
            }
            Text(row.pronunciation)
                .italic()
                .foregroundStyle(PagePalette.text.opacity(0.6))
                .lineLimit(1)
                .accessibilityLabel(row.pronunciation == "—" ? "No pronunciation" : row.pronunciation)
            PageTintChip(text: row.source.title, tint: DictionarySourceTint.color(row.source))
                .help(row.origin)
            PageTintChip(
                text: row.prompt.text,
                tint: row.prompt.isInPrompt ? PagePalette.dictation : PagePalette.neutral
            )
            .help(row.prompt.spoken)
            .accessibilityLabel(row.prompt.spoken)
            Text("\(row.timesUsed)×")
                .monospacedDigit()
                .foregroundStyle(PagePalette.text.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(row.timesUsedSpoken)
            Text("\(row.timesUndone)×")
                .monospacedDigit()
                .foregroundStyle(undoneColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(row.timesUndoneSpoken)
            controls
        }
        .font(.system(size: 13))
        .opacity(row.isRetired ? 0.6 : 1)
        .padding(.horizontal, PageMetrics.rowInset)
        .padding(.vertical, 11)
        .background(isHovered ? PagePalette.text.opacity(0.03) : .clear)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .rowActions((row.tryIt.map { [$0] } ?? []) + row.actions, onIntent: onIntent)
    }

    /// Amber once undone, red when the undos are what is retiring it, quiet otherwise.
    private var undoneColor: Color {
        if row.undoneIsConcerning { return .criticalInk }
        return row.hasBeenUndone ? PagePalette.clipboardInk : PagePalette.faint
    }

    /// Restore is drawn at rest on a retired word; Delete's glyph waits for the pointer or the keyboard.
    private var controls: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            if let tryIt = row.tryIt {
                PageRowIconButton(
                    action: tryIt,
                    isShown: row.trial != nil
                        || RowReveal.isDrawn(isHovered: isHovered, focusedControl: focusedControl),
                    onIntent: onIntent
                )
                .focused($focusedControl, equals: tryIt.id)
            }
            ForEach(row.actions) { action in
                if action.isDestructive {
                    PageRowIconButton(
                        action: action,
                        isShown: RowReveal.isDrawn(isHovered: isHovered, focusedControl: focusedControl),
                        onIntent: onIntent
                    )
                    .focused($focusedControl, equals: action.id)
                } else {
                    Button(action.title) { onIntent(action.intent) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.clipboardInk)
                        .lineLimit(1)
                        .fixedSize()
                        .focused($focusedControl, equals: action.id)
                }
            }
        }
        // The row's height comes from its text, as in the design; the 22-point hit area overhangs it.
        .frame(maxWidth: .infinity, maxHeight: 19, alignment: .trailing)
    }
}

/// The refused spellings behind a disclosure, each with Allow again drawn at rest.
struct DictionaryNotLearningView: View {
    let section: DictionaryNotLearning
    var onIntent: (MainIntent) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.faint)
                    .padding(.bottom, 8)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(section.rows) { row in
                        if row.id != section.rows.first?.id { PageDivider() }
                        HStack {
                            Text(row.word)
                                .foregroundStyle(PagePalette.text)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Button(row.allow.title) { onIntent(row.allow.intent) }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(PagePalette.clipboardInk)
                                .accessibilityLabel("\(row.allow.title), \(row.word)")
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, PageMetrics.rowInset)
                        .padding(.vertical, 9)
                    }
                }
                .pageCard()
            }
            .padding(.top, 8)
        } label: {
            PageSectionLabel(text: section.title)
        }
    }
}

/// A try's one line, a spinner while it runs, and the "Say it like" a miss offers.
struct DictionaryTrialView: View {
    let line: DictionaryTrialLine
    var onIntent: (MainIntent) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if line.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(line.text)
                .font(.system(size: 11.5))
                .foregroundStyle(PagePalette.text)
                .lineLimit(2)
            if let offer = line.offer {
                Button(offer.title) { onIntent(offer.intent) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.clipboardInk)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Which accent each source chip wears.
enum DictionarySourceTint {
    static func color(_ source: DictionarySource) -> Color {
        switch source {
        case .added: PagePalette.dictation
        case .learned: PagePalette.suggestion
        case .seen: PagePalette.info
        case .shipped: PagePalette.neutral
        case .retired: PagePalette.clipboard
        }
    }
}

/// Today's corrections: a label, then up to three cards, each with its way back.
struct DictionaryFixesView: View {
    let label: String
    let fixes: [CorrectionRow]
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageSectionLabel(text: label)
            HStack(alignment: .top, spacing: 10) {
                ForEach(fixes) { DictionaryFixCard(fix: $0, onIntent: onIntent) }
                // Keeps a card a third of the row wide when fewer than three were fixed.
                ForEach(fixes.count..<max(fixes.count, 3), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
    }
}

/// One correction: when, what was heard struck through, what was written, and Undo.
struct DictionaryFixCard: View {
    let fix: CorrectionRow
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(fix.when)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PagePalette.faint)
                Spacer(minLength: 6)
                if let undo = fix.undo {
                    Button {
                        onIntent(undo.intent)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                            Text(undo.title)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(PagePalette.text.opacity(0.6))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 5) {
                Text(fix.heard)
                    .strikethrough()
                    .foregroundStyle(PagePalette.faint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PagePalette.dictation)
                    .accessibilityHidden(true)
                Text(fix.wrote)
                    .fontWeight(.semibold)
                    .foregroundStyle(PagePalette.text)
            }
            .font(.system(size: 13))
            .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("“\(fix.heard)” was changed to “\(fix.wrote)” at \(fix.when)")
    }
}
