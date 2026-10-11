# The Hinglish and context cases in the evaluation corpus

`EvaluationCorpus` holds the hand-written cases every clean-up candidate is measured against, as
data in `Sources/UttrflowEval/Resources/Corpus/`. Each is something a person would dictate, and
several encode a failure a real model produced. This page explains the `multilingual` and
`contextual` cases; results are in [`bakeoff.md`](bakeoff.md).

## Hinglish

Hindi is written back in the Latin alphabet, the way people type it in a chat window
([`latin-output.md`](latin-output.md)). That is a real transformation that deterministic rules do
not fully do, so these cases measure clean-up rather than whether a model leaves the input alone.
None of these sentences appears in the prompt, and `ScorerTests` enforces that.
`hinglish-trailing-english` holds a trailing English clause that must stay English rather than be
rewritten into Hinglish; `hindi-translation-refused` holds the case a translation must not pass.

## Why the context cases come in pairs

One context case proves nothing: if the answer looks right, nothing says whether the context
caused it or plain dictation would have said the same. So the cases come in pairs — identical
spoken words, two windows, two references — and each half is scored on its own. Only both halves
passing shows the model moved with the window.

The other half of the job is restraint. Context tempts a model to finish the thought the speaker
only started: a sort direction nobody asked for, a function body around a sentence about a
function, a file extension dragged in from a window title. `mustNotAdd` guards those.

- **Pair one** (`sql-editor-totals`, `chat-totals`): an utterance becoming prose or becoming SQL.
  "Sort by the total" says nothing about direction, so `DESC` tells the user something they did
  not say; `LIMIT` is the same failure, since no number was spoken. The SQL half fails by design:
  context corrects spelling and does not write code ([`bakeoff.md`](bakeoff.md)).
- **Pair two** (`slack-name-spelling`, `notes-name-spelling`): a recogniser spells a name the way
  it sounds. The channel title says how this person spells it, so the title wins; with no title
  the transcript wins and nothing is invented.
- **Pair three** (`editor-identifier-casing` and its control): two spoken words are one identifier
  only because the window title says so. The guards cover the two ways the title gets over-read:
  the extension coming along, and a second identifier manufactured out of "card scanner" by
  analogy with the first.
- **Selected text** (`editor-selected-identifier`) is the strongest evidence there is, and it still
  only licenses the name the user pointed at. The replacement they described aloud stays prose.
- **Describing a function is not asking for one.** In a chat window the sentence is a message to a
  colleague, and any keyword at all means the model answered the request instead of transcribing
  it.
- **Context has to be able to change nothing.** Most of what anyone dictates into an editor is an
  ordinary sentence, and a model that treats every window as an instruction about output format
  makes the common case worse to buy the rare one.

## The guards

`mustNotAdd` matches ordinary words on whole-word boundaries, inside one sentence, and anything
with no letters or digits (a lone brace) literally. Braces are guarded alongside the keywords that
would sit beside them, because a keyword is the surer sign that prose became code.
