// The Dictionary page's editor card: the word, its pronunciations, a try, and save.

import UttrflowUX
import SwiftUI

/// The word being written, on a card over the table shaped like the snippet editor.
struct DictionaryEditorView: View {
    let editor: DictionaryEditor
    @Binding var draft: DictionaryDraft
    var onIntent: (MainIntent) -> Void

    /// Which field has the caret; the spelling takes it as the card opens.
    @FocusState private var focused: Field?

    /// The card's two fields.
    enum Field { case word, pronunciation }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New word")
                    .font(BrandFont.display(size: 14, weight: .semibold))
                    .foregroundStyle(PagePalette.text)
                Spacer(minLength: 0)
                PageBadge(text: editor.badge.text)
            }
            PageEditorField(
                label: editor.wordLabel, symbolName: "character.cursor.ibeam",
                tint: PagePalette.dictation
            ) {
                TextField("", text: word).textFieldStyle(.plain)
                    .focused($focused, equals: .word)
                    .onSubmit(submit)
            }
            VStack(alignment: .leading, spacing: 5) {
                PageEditorField(
                    label: editor.pronunciationLabel, symbolName: "ear", tint: PagePalette.suggestion
                ) {
                    TextField("", text: pronunciation).textFieldStyle(.plain)
                        .focused($focused, equals: .pronunciation)
                        .onSubmit(submit)
                }
                Text(editor.pronunciationHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PagePalette.faint)
                if let note = editor.pronunciationNote {
                    Text(note)
                        .font(.system(size: 11.5))
                        .foregroundStyle(PagePalette.text)
                }
            }
            if let tryIt = editor.tryIt {
                HStack(alignment: .center, spacing: 10) {
                    PageButton(action: tryIt, onIntent: onIntent)
                        .disabled(editor.trial?.isBusy == true)
                    if let trial = editor.trial {
                        DictionaryTrialView(line: trial, onIntent: onIntent)
                    }
                }
            }
            PageEditorFooter(
                problem: editor.problem, cancel: editor.cancel, save: save,
                canSave: editor.canSave, onIntent: onIntent)
            if let replace = editor.replace {
                HStack {
                    Spacer(minLength: 0)
                    PageButton(action: replacing(replace), onIntent: onIntent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pageCard(edge: PagePalette.dictation.opacity(0.35))
        .onAppear { focused = .word }
        .onExitCommand { onIntent(editor.cancel.intent) }
    }

    /// Return saves a word that can be saved, and does nothing to one that cannot.
    private func submit() {
        if editor.canSave { onIntent(save.intent) }
    }

    /// Rebuilt from what is in the fields now, not from the presentation drawn a keystroke ago.
    private var save: MainAction {
        if case .replaceWord = editor.save.intent { return replacing(editor.save) }
        return MainAction(
            title: editor.save.title,
            intent: .saveWord(word: draft.word, pronunciation: draft.pronunciation))
    }

    /// The Replace action rebuilt from the fields now, as Save is.
    private func replacing(_ replace: MainAction) -> MainAction {
        guard case .replaceWord(let id, _, _) = replace.intent else { return replace }
        return MainAction(
            title: replace.title,
            intent: .replaceWord(
                id, word: draft.word,
                pronunciation: draft.editing == nil
                    ? DictionaryPresenter.keeping(editor.kept, adding: draft.pronunciation)
                    : draft.pronunciation))
    }

    private var word: Binding<String> {
        Binding(
            get: { draft.word },
            set: {
                draft = DictionaryDraft(
                    editing: draft.editing, word: $0, pronunciation: draft.pronunciation)
            })
    }

    private var pronunciation: Binding<String> {
        Binding(
            get: { draft.pronunciation },
            set: {
                draft = DictionaryDraft(editing: draft.editing, word: draft.word, pronunciation: $0)
            })
    }
}
