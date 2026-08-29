import UttrflowUX
import SwiftUI

/// Triggers you say, and the text you get instead.
struct SnippetsPageView: View {
    let presentation: SnippetsPresentation
    /// What is being typed into the inline editor. Held by the window rather than here
    /// so the fields survive the page being redrawn under them.
    @Binding var draft: SnippetDraft
    var onIntent: (MainIntent) -> Void

    private let columns = [
        MainColumn(title: "Trigger", width: 140),
        MainColumn(title: "Types", width: nil),
        MainColumn(title: "Used", width: 40, alignment: .trailing),
        MainColumn(title: "Last used", width: 70),
    ]

    var body: some View {
        if let empty = presentation.emptyState {
            VStack(spacing: 0) {
                MainEmptyStateView(state: empty, onIntent: onIntent)
                    .overlay(alignment: .bottom) {
                        if let example = presentation.example {
                            SnippetExampleCard(example: example).padding(.bottom, 8)
                        }
                    }
            }
        } else {
            // The editor sits beside the list rather than under it. Underneath, the
            // fields arrived below the fold on a page of any length, and the row being
            // edited scrolled out of sight the moment you started typing — which is the
            // one row you want to keep looking at.
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    MainSectionLabel(text: presentation.caption)
                        .padding(.bottom, 7)
                    ScrollView {
                        MainRowsCard(
                            rows: presentation.rows, header: MainTableHeader(columns: columns)
                        ) { row in
                            SnippetRowView(row: row, columns: columns, onIntent: onIntent)
                        }
                    }
                    if let footnote = presentation.footnote {
                        MainFootnote(text: footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let editor = presentation.editor {
                    SnippetEditorView(editor: editor, draft: $draft, onIntent: onIntent)
                        .frame(width: 316)
                }
            }
        }
    }
}

/// One snippet.
struct SnippetRowView: View {
    let row: SnippetRow
    let columns: [MainColumn]
    var onIntent: (MainIntent) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            MainPillView(pill: row.trigger)
                .frame(width: columns[0].width, alignment: .leading)
            Text(row.text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                ForEach(row.actions) { MainIconButton(action: $0, onIntent: onIntent) }
            }
            // Hidden rather than removed, as on Dictation and Dictionary: building these
            // only while hovered took Edit and Delete out of the accessibility tree
            // entirely, so a VoiceOver user could not reach either — and it made the row
            // change width as the pointer crossed it.
            .opacity(isHovered ? 1 : 0)
            Text(row.timesUsed)
                .monospacedDigit()
                .frame(width: columns[2].width, alignment: .trailing)
            Text(row.lastUsed)
                .foregroundStyle(.secondary)
                .frame(width: columns[3].width, alignment: .leading)
        }
        .font(.system(size: MainMetrics.calloutSize))
        .padding(.horizontal, MainMetrics.rowPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.mainHover : .clear)
        .onHover { isHovered = $0 }
        .rowActions(row.actions, onIntent: onIntent)
    }
}

/// The inline editor, in the row where the snippet will end up.
struct SnippetEditorView: View {
    let editor: SnippetEditor
    @Binding var draft: SnippetDraft
    var onIntent: (MainIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                label(editor.triggerLabel)
                Spacer(minLength: 0)
                MainPillView(pill: editor.badge)
            }
            TextField("", text: trigger)
                .textFieldStyle(.roundedBorder)
            label(editor.textLabel)
                .padding(.top, 2)
            TextEditor(text: text)
                .font(.system(size: MainMetrics.calloutSize))
                .frame(height: 84)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.mainCard, in: .rect(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.mainSeparator, lineWidth: 0.5))
            HStack(spacing: 8) {
                // The reason it cannot be saved, beside the button that cannot save it.
                // A disabled button with no explanation is a bug the user cannot report.
                if let problem = editor.problem {
                    Text(problem)
                        .font(.system(size: MainMetrics.footnoteSize))
                        .foregroundStyle(Color.dockWarning)
                }
                Spacer(minLength: 0)
                MainActionButton(action: editor.cancel, onIntent: onIntent)
                MainActionButton(action: save, isProminent: true, onIntent: onIntent)
                    .disabled(!editor.canSave)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A panel, because this is one of the things a reader chooses between: it is
        // being filled in, not read past.
        .background(Color.mainCard, in: .rect(cornerRadius: MainMetrics.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: MainMetrics.cardRadius)
                .strokeBorder(Color.mainSeparator, lineWidth: 0.5))
    }

    /// Rebuilt from what is currently in the fields rather than from the presentation,
    /// which was drawn a keystroke ago.
    private var save: MainAction {
        MainAction(
            title: editor.save.title,
            intent: .saveSnippet(
                trigger: draft.trigger, text: draft.text, replacing: editor.editing))
    }

    private var trigger: Binding<String> {
        Binding(
            get: { draft.trigger },
            set: { draft = SnippetDraft(editing: draft.editing, trigger: $0, text: draft.text) })
    }

    private var text: Binding<String> {
        Binding(
            get: { draft.text },
            set: { draft = SnippetDraft(editing: draft.editing, trigger: draft.trigger, text: $0) })
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: MainMetrics.footnoteSize))
            .foregroundStyle(.secondary)
            .frame(width: 88, alignment: .leading)
    }
}

/// The worked example on the empty page, so the idea lands before the form does.
struct SnippetExampleCard: View {
    let example: SnippetExample

    var body: some View {
        MainCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(example.heading.uppercased())
                    .font(.system(size: MainMetrics.footnoteSize, weight: .semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    MainPillView(pill: example.trigger)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(example.text)
                        .font(.system(size: MainMetrics.calloutSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 400)
        .accessibilityElement(children: .combine)
    }
}
