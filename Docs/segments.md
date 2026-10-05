# Segment requirements

What each kind of speaker needs from dictation, and which corpus slice, measurement or issue
covers that need. The release gate in [accuracy-targets.md](accuracy-targets.md) judges
"good enough" per slice; this page says which slice stands for whom.

A cell holds evidence: a clean-up corpus category (`EvaluationCase.Category`), a
transcription stressor (`TranscriptionCase.Stressor`), a measurement page, or an issue. A cell
with no evidence says **unknown** and names the probe that would settle it. A **gap** is a need
nothing serves yet, and it always names an open issue.

## Columns

- **Vocabulary**: the words recognition must get right.
- **Structure**: the shape of the text: sentences, paragraphs, lists, one-line values, code.
- **Speed**: how fast and how long the person speaks.
- **Commands**: spoken marks, layout and key commands the person relies on.
- **Error cost**: what one wrong word costs, in the classes of
  [accuracy-targets.md](accuracy-targets.md#the-error-taxonomy).
- **Privacy**: what the person's text contains that must stay on the Mac. Every row inherits
  [offline.md](offline.md) and [persona-threat-model.md](persona-threat-model.md); the cell
  names only what is extra.

## By who is speaking

| Segment | Vocabulary | Structure | Speed | Commands | Error cost | Privacy |
|---|---|---|---|---|---|---|
| Developers | `technical` category and stressor; identifiers #4194, naming #4214 | code destinations, [formatting-matrix.md](formatting-matrix.md); prose inside an editor #4251 | unknown: probe #3587 | key commands #4209; command lines #4441 | class 1: one wrong character breaks the code | secrets in copied code, [clipboard-secrets.md](clipboard-secrets.md) |
| Writers | `everyday`, `grammar` categories | paragraphs and lists, formatting corpus #3818 | long dictations: gap #4181 | spoken marks #3426, new line and paragraph #2392 | class 1 for a rewrite; dialect must stay (`grammar`) | no extra need known |
| Students | gap #4980 | gap #4980 | unknown: probe #3587 | unknown: probe #4980 | unknown: probe #4980 | no extra need known |
| Support agents | gap #4980; product names via packs #3659 | short replies, chat profile #4451 | unknown: probe #3587 | unknown: probe #4980 | class 1 for a customer's name or number (`properNouns`, `digits`) | customer data in replies; gap #4980 |
| Clinicians | gap #3813, packs #3659 | unknown: probe #3587 | unknown: probe #3587 | unknown: probe #3587 | class 1: a wrong drug, dose or negation | patient data, which [offline.md](offline.md) keeps on the Mac |
| Lawyers | gap #3813, packs #3659 | unknown: probe #3587 | unknown: probe #3587 | unknown: probe #3587 | class 1: a dropped negation or wrong number | client data, as above |
| Researchers | gap #3813; citations gap #4980 | gap #4980 | unknown: probe #3587 | unknown: probe #4980 | class 1 for a term or number (`technical`, `digits`) | no extra need known |
| People who rely on voice because of a motor or vision impairment | as their other rows | as their other rows | unknown: probe #3587 | [hands-free session](#a-hands-free-session): start by key only #5539, stop by voice #4314 #4319 | every correction needs the command key and no edit command exists: gap #2389 | no extra need known |
| Non-native English speakers | `properNouns` stressor; accent cohorts, [measuring-accuracy.md](measuring-accuracy.md) | as their other rows | unknown: probe #4527 | as their other rows | class 1; accent confusions #4511 | no extra need known |
| Hinglish speakers | `multilingual` category, [eval-context-cases.md](eval-context-cases.md); Indian pack #4301 | as their other rows | unknown: probe #3587 | spoken command names per language #4351; self-correction triggers #4051 | class 1 for Devanagari or a translation, [latin-output.md](latin-output.md) | no extra need known |
| Speakers with speech differences | `falseStarts` stressor | as their other rows | slow and effortful speech: gap #3804; pause length #4052 | as their other rows | class 1 for an over-deleted word: gap #3779 | no extra need known |

## By where the text goes

| Segment | Vocabulary | Structure | Speed | Commands | Error cost | Privacy |
|---|---|---|---|---|---|---|
| Long documents | as the speaker's row | paragraphs and lists #3818; structure invariants #4013 | long Accessibility writes: gap #4181 | new line and paragraph #2392 | class 2 for layout; class 1 for a double insert #4181 | no extra need known |
| Chat | as the speaker's row | one short line, `oneLineField` category; closing stop #4451 | unknown: probe #3587 | unknown: probe #3587 | class 2 for a wrong stop | no extra need known |
| Terminals | `technical` stressor; flags #4442, #4443 | prose or shell from the prompt #4217; profile #4413 | unknown: probe #3587 | key commands off by default #4209 | class 1: a wrong flag runs a different command | commands carrying secrets, [clipboard-secrets.md](clipboard-secrets.md) |

## A hands-free session

One hands-free session (start, dictate, stop, correct) through the real controller and pipeline,
counting key presses and what VoiceOver is told: `swift test --filter HandsFreeSessionProbeTests`.

| Step | Key presses | VoiceOver hears | Gap |
|---|---|---|---|
| Start | 2: a double tap | "Listening." twice | key only #5539; announced twice #5538 |
| Dictate | 0 | nothing | none |
| Stop | 2: a double tap | "Inserted:" and the words | stop by voice #4314, #4319 |
| Correct | 1: a hold of the command key | "That isn't an edit command Uttrflow knows" | no edit command #2389 |
