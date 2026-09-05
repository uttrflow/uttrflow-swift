# The context pairs in the evaluation corpus

`EvaluationCorpus` (`Sources/UttrflowEval/EvaluationCorpus.swift`) holds the hand-written cases
every clean-up candidate is measured against. Each is something a person would dictate, and
several encode a failure a real model produced. Results are in `Docs/bakeoff.md`.

## Hinglish

Hindi is written back in the Latin alphabet, the way people type it in a chat window. That is a
real transformation, deterministic rules cannot do it, so these cases measure clean-up rather
than whether a model leaves the input alone. None of these sentences appears in the prompt, and
a test enforces that. One case exists because a trailing English clause was being rewritten into
Hinglish, which the speaker never said.

## Why the context cases come in pairs

A single context case proves nothing: if the answer looks right you cannot tell whether the
context caused it or whether plain dictation would have said the same thing. So the cases come
in pairs, identical spoken words, two windows, two references, and a pair passes only when the
model moves between them.

The other half of the job is restraint. Context tempts a model to finish the thought the speaker
only started: a sort direction nobody asked for, a function body around a sentence about a
function, a file extension dragged in from a window title. `mustNotAdd` guards those.

- **Pair one**: the difference between an utterance becoming prose and becoming SQL. "Sort by
  the total" says nothing about direction, so a model that writes `DESC` has told the user
  something they did not say; `LIMIT` is the same failure, no number was spoken so none is owed.
- **Pair two**: a recogniser spells a name the way it sounds. The channel title says how this
  person spells it, so the title wins; with no title, the transcript wins and nothing is invented.
- **Pair three**: two spoken words are one identifier only because the window title says so.
  The guards cover the two ways the title gets over-read: the extension coming along, and a
  second identifier manufactured out of "card scanner" by analogy with the first.
- **Selected text** is the strongest evidence there is, and it still only licenses the name the
  user pointed at. The replacement they described out loud stays the prose they spoke.
- **Describing a function is not asking for one.** In a chat window the sentence is a message to
  a colleague, and any keyword at all means the model answered the request instead of
  transcribing it.
- **Context has to be able to change nothing.** Most of what anyone dictates into an editor is
  an ordinary sentence, and a model that treats every window as an instruction about output
  format makes the common case worse to buy the rare one.

## The guards

`mustNotAdd` matches ordinary words on whole-word boundaries, and anything with no letters or
digits (a lone brace) literally. Braces are guarded alongside the keywords that would sit beside
them, because a keyword is the surer sign that prose became code.
