import UttrflowUX
import SwiftUI

/// The words Uttrflow knows and a general model does not.
struct DictionaryPageView: View {
    let presentation: DictionaryPresentation
    /// What is being typed into the inline editor. Held by the window rather than here
    /// so the fields survive the page being redrawn under them.
    @Binding var draft: DictionaryDraft
    var onIntent: (MainIntent) -> Void

    /// The artboard's column widths. Layout, so they live here.
    private let columns = [
        MainColumn(title: "Word", width: 150),
        MainColumn(title: "Sounds like", width: 104),
        MainColumn(title: "Where from", width: 106),
        MainColumn(title: "Added", width: 60),
        MainColumn(title: "Used", width: 38, alignment: .trailing),
        MainColumn(title: "Undone", width: 46, alignment: .trailing),
        MainColumn(title: "", width: nil, alignment: .trailing),
    ]

    var body: some View {
        if let empty = presentation.emptyState {
            MainEmptyStateView(state: empty, onIntent: onIntent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                MainSectionLabel(text: presentation.caption)
                    .padding(.bottom, 7)
                ScrollView {
                    VStack(spacing: 0) {
                        MainRowsCard(
                            rows: presentation.rows, header: MainTableHeader(columns: columns)
                        ) { row in
                            DictionaryRowView(row: row, columns: columns, onIntent: onIntent)
                        }
                        if let editor = presentation.editor {
                            DictionaryEditorView(
                                editor: editor, draft: $draft, onIntent: onIntent)
                        }
                    }
                }
                if let footnote = presentation.footnote {
                    MainFootnote(text: footnote)
                }
            }
        }
    }
}

/// One word.
///
/// A retired row is dimmed — but only the parts of it that describe the word. The
/// control that un-retires it keeps its full contrast, because a way out that is harder
/// to see than the problem is not a way out.
struct DictionaryRowView: View {
    let row: DictionaryRow
    let columns: [MainColumn]
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    /// Dimmed for a retired word.
    private var descriptionOpacity: Double { row.isRetired ? 0.45 : 1 }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(row.word).fontWeight(.medium)
                if let badge = row.badge { MainPillView(pill: badge) }
                Spacer(minLength: 0)
            }
            .frame(width: columns[0].width, alignment: .leading)
            .opacity(descriptionOpacity)

            quiet(row.pronunciation, width: columns[1].width)
            quiet(row.origin, width: columns[2].width)
            quiet(row.added, width: columns[3].width)

            Text(row.timesUsed)
                .monospacedDigit()
                .frame(width: columns[4].width, alignment: .trailing)
                .opacity(descriptionOpacity)
            Text(row.timesUndone)
                .monospacedDigit()
                .foregroundStyle(row.undoneIsConcerning ? Color.dockRecording : .secondary)
                .frame(width: columns[5].width, alignment: .trailing)
                .opacity(descriptionOpacity)

            HStack(spacing: 5) {
                Spacer(minLength: 0)
                ForEach(row.actions) { action in
                    MainActionButton(action: action, onIntent: onIntent)
                        .opacity(isHovered || isDrawnAtRest(action) ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: MainMetrics.calloutSize))
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions(row.actions, onIntent: onIntent)
        .accessibilityElement(children: .contain)
    }

    /// Restore is drawn at rest for a retired word; everything else waits for the
    /// pointer, so a table of thirty words is a table and not a wall of buttons.
    ///
    /// *Drawn*, not *built*. Every action is in the row whatever the pointer is doing —
    /// filtering them out made Delete unreachable by keyboard and invisible to VoiceOver,
    /// and made the row change shape as the pointer crossed it.
    private func isDrawnAtRest(_ action: MainAction) -> Bool {
        row.isRetired && !action.isDestructive
    }

    private func quiet(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .opacity(descriptionOpacity)
    }
}

/// The inline editor, in the row where the word will end up.
///
/// Deliberately shaped like ``SnippetEditorView``: the two pages ask for two fields and
/// a Save, and a user who has added a snippet should not have to learn a second form.
struct DictionaryEditorView: View {
    let editor: DictionaryEditor
    @Binding var draft: DictionaryDraft
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                MainEditorLabel(text: editor.wordLabel)
                TextField("", text: word)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                MainPillView(pill: editor.badge)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                MainEditorLabel(text: editor.pronunciationLabel)
                TextField("", text: pronunciation)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Text(editor.pronunciationHint)
                    .font(.system(size: MainMetrics.footnoteSize))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            MainEditorFooter(
                problem: editor.problem, cancel: editor.cancel, save: save,
                canSave: editor.canSave, onIntent: onIntent)
        }
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mainHover)
        .overlay(alignment: .top) { MainDivider() }
    }

    /// Rebuilt from what is currently in the fields rather than from the presentation,
    /// which was drawn a keystroke ago.
    private var save: MainAction {
        MainAction(
            title: editor.save.title,
            intent: .saveWord(word: draft.word, pronunciation: draft.pronunciation))
    }

    private var word: Binding<String> {
        Binding(
            get: { draft.word },
            set: { draft = DictionaryDraft(word: $0, pronunciation: draft.pronunciation) })
    }

    private var pronunciation: Binding<String> {
        Binding(
            get: { draft.pronunciation },
            set: { draft = DictionaryDraft(word: draft.word, pronunciation: $0) })
    }
}
