// The Snippets page: the editor card, the table, and the empty page.

import UttrflowUX
import SwiftUI

/// Triggers you say, and the text you get instead.
struct SnippetsPageView: View {
    let presentation: SnippetsPresentation
    /// What is being typed into the editor, held by the window so it survives a redraw.
    @Binding var draft: SnippetDraft
    var onIntent: (MainIntent) -> Void

    /// The artboard's columns: trigger, text, used, last used, and the row's controls.
    static let widths: [PageColumnWidth] = [.fixed(150), .share(1), .fixed(60), .fixed(90), .fixed(60)]

    var body: some View {
        if let empty = presentation.emptyState, presentation.editor == nil {
            MainEmptyStateView(state: empty, onIntent: onIntent)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let editor = presentation.editor {
                        SnippetEditorView(editor: editor, draft: $draft, onIntent: onIntent)
                            .padding(.bottom, 14)
                    }
                    if !presentation.rows.isEmpty {
                        table
                    }
                    if let footnote = presentation.footnote {
                        MainFootnote(text: footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var table: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            PageTableHeader(titles: ["When I say", "Type this", "Used", "Last", ""], widths: Self.widths)
            ForEach(presentation.rows) { row in
                PageDivider()
                SnippetRowView(row: row, onIntent: onIntent)
            }
        }
        .pageCard()
    }
}

/// One snippet; Edit sits at rest and Delete waits for the pointer.
struct SnippetRowView: View {
    let row: SnippetRow
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false
    @FocusState private var focusedControl: String?

    var body: some View {
        PageColumns(widths: SnippetsPageView.widths) {
            SnippetTriggerPill(text: row.trigger.text, tint: SnippetTint.color(row.tint))
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.text.replacingOccurrences(of: "\n", with: " "))
                    .foregroundStyle(PagePalette.text.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let warning = row.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("\(row.timesUsed)×")
                .monospacedDigit()
                .foregroundStyle(PagePalette.text.opacity(0.6))
                .accessibilityLabel(row.timesUsedSpoken)
            Text(row.lastUsed)
                .font(.system(size: 12))
                .foregroundStyle(PagePalette.faint)
                .lineLimit(1)
                .accessibilityLabel(row.lastUsed == "Never" ? "Never used" : "Last used \(row.lastUsed)")
            controls
        }
        .font(.system(size: 13))
        .padding(.horizontal, PageMetrics.rowInset)
        .padding(.vertical, 11)
        .background(isHovered ? PagePalette.text.opacity(0.03) : .clear)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .rowActions(row.actions, onIntent: onIntent)
    }

    /// Delete's glyph waits for the pointer or the keyboard, left of Edit so Edit keeps the row's end.
    private var controls: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            ForEach(trailingOrder) { action in
                PageRowIconButton(
                    action: action,
                    isShown: !action.isDestructive
                        || RowReveal.isDrawn(isHovered: isHovered, focusedControl: focusedControl),
                    onIntent: onIntent
                )
                .focused($focusedControl, equals: action.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Delete first, so the always-drawn Edit ends the row where the design puts it.
    private var trailingOrder: [MainAction] {
        row.actions.filter(\.isDestructive) + row.actions.filter { !$0.isDestructive }
    }
}

/// The phrase you say, as a tinted pill with a microphone.
struct SnippetTriggerPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "mic")
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(PagePalette.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
        .fixedSize(horizontal: false, vertical: true)
        .help(text)
    }
}

/// The four accents a trigger pill cycles through, in the artboard's order.
enum SnippetTint {
    static func color(_ index: Int) -> Color {
        switch index % SnippetsPresenter.tints {
        case 0: PagePalette.clipboard
        case 1: PagePalette.info
        case 2: PagePalette.suggestion
        default: PagePalette.dictation
        }
    }
}

/// The snippet being written, on a card over the table.
struct SnippetEditorView: View {
    let editor: SnippetEditor
    @Binding var draft: SnippetDraft
    var onIntent: (MainIntent) -> Void

    /// Which field has the caret; the trigger for a new snippet, the text for one being edited.
    @FocusState private var focused: Field?

    /// The card's two fields.
    enum Field { case trigger, text }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editor.title)
                    .font(BrandFont.display(size: 14, weight: .semibold))
                    .foregroundStyle(PagePalette.text)
                Spacer(minLength: 0)
                PageBadge(text: editor.badge.text)
            }
            PageEditorField(label: editor.triggerLabel, symbolName: "mic", tint: PagePalette.dictation) {
                TextField("", text: trigger).textFieldStyle(.plain)
                    .focused($focused, equals: .trigger)
                    .onSubmit(submit)
            }
            PageEditorField(label: editor.textLabel, symbolName: "keyboard", tint: PagePalette.suggestion) {
                TextEditor(text: text)
                    .focused($focused, equals: .text)
                    .onKeyPress(.return, phases: .down) { press in
                        guard
                            SnippetEditorKeyboard.savesTextEditorReturn(
                                command: press.modifiers.contains(.command))
                        else { return .ignored }
                        submit()
                        return .handled
                    }
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .lineSpacing(3)
                    .frame(minHeight: 44, maxHeight: 180)
                    .padding(.horizontal, -5)
            }
            if let arrival = editor.arrival {
                HStack(spacing: 8) {
                    Text(arrival)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.text)
                    Spacer(minLength: 0)
                    if let saveArrived = editor.saveArrived {
                        PageButton(action: saveArrived, onIntent: onIntent)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if let note = editor.dictionaryNote {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let caution = editor.caution {
                    Text(caution)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ApplicationScopeRow(line: editor.scope, applications: applications)
            PageEditorFooter(
                problem: editor.problem, cancel: editor.cancel, save: save,
                canSave: editor.canSave, onIntent: onIntent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard(edge: PagePalette.dictation.opacity(0.35))
        .onAppear { focused = editor.editing == nil ? .trigger : .text }
        .onExitCommand { onIntent(editor.cancel.intent) }
    }

    /// Return saves only when the current draft passes validation.
    private func submit() {
        guard let intent = SnippetEditorKeyboard.saveIntent(canSave: editor.canSave, save: save.intent)
        else { return }
        onIntent(intent)
    }

    /// Rebuilt from what is in the fields now, not from the presentation drawn a keystroke ago.
    private var save: MainAction {
        MainAction(
            title: editor.save.title,
            intent: .saveSnippet(
                trigger: draft.trigger, text: draft.text, applications: draft.applications,
                replacing: editor.editing))
    }

    private var trigger: Binding<String> {
        Binding(
            get: { draft.trigger },
            set: {
                draft = SnippetDraft(
                    editing: draft.editing, trigger: $0, text: draft.text, applications: draft.applications)
            })
    }

    private var text: Binding<String> {
        Binding(
            get: { draft.text },
            set: {
                draft = SnippetDraft(
                    editing: draft.editing, trigger: draft.trigger, text: $0, applications: draft.applications
                )
            })
    }

    private var applications: Binding<[String]> {
        Binding(
            get: { draft.applications },
            set: {
                draft = SnippetDraft(
                    editing: draft.editing, trigger: draft.trigger, text: draft.text, applications: $0)
            })
    }
}

enum SnippetEditorKeyboard {
    static func savesTextEditorReturn(command: Bool) -> Bool { command }

    static func saveIntent(canSave: Bool, save: MainIntent) -> MainIntent? {
        canSave ? save : nil
    }
}
