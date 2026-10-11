# Disfluent speech

The clean-up's stammer and repeated-phrase rules were tuned on hesitation in fluent speech, and
[disfluency-deletion.md](disfluency-deletion.md) scores them on invented text. For a person who
stutters, a repeated sound or a block is the common case rather than the exception, and for slow
or effortful speech the recogniser itself can fail. This page is the protocol for recording such
speech, the schema its labels follow, and what the report measures. The code is
`Sources/UttrflowEval/DisfluentSpeech.swift`; `DisfluentSpeechTests` checks the schema and every
metric on invented takes.

## Recording protocol

1. **Consent first, in writing.** Each speaker signs a consent form before the first take. It
   says the audio stays on the recording Mac, is used only to measure Uttrflow, is never
   committed, uploaded or shared, and is deleted when the speaker asks. The form's version is
   written on every take as `consent`; a take with audio and no consent version is refused.
2. **A label, never a name.** A speaker is `s01`, `s02` and so on, a label the corpus catalogue
   accepts (`CorpusSlug`). The list that maps a label to a person is kept with the signed forms,
   off the recording Mac's corpus folder.
3. **One folder, local only.** The folder holds `corpus.json` and one subfolder per speaker
   label; a take's `audio` is a file name inside its speaker's subfolder, with no path in it.
   Nothing in the folder goes into the repository: `make audio-audit` refuses audio in the tree
   and `make pii-audit` refuses personal data.
4. **Withdrawal.** Deleting a speaker's subfolder and their takes from `corpus.json` removes them;
   the report is rerun without them.
5. **The bar for a decision.** At least 100 takes from at least 5 speakers
   (`DisfluentSpeechCorpus.isEnoughToDecide`). Each speaker also records fluent takes, so every
   row is read against the same voices speaking fluently.

## Labels

A take is one `DisfluentUtterance`: `id`, `speaker`, `pattern`, `marked`, and for a real take
`audio` and `consent`. `marked` is what was said, with every sound or word the speaker did not
mean inside braces:

| Pattern | Marked | Meant |
|---|---|---|
| `sound-repetition` | `{b-b-}but I want it` | but I want it |
| `part-word-repetition` | `buy a {ba- ba-}banana` | buy a banana |
| `whole-word-repetition` | `{I I} I need the report` | I need the report |
| `prolongation` | `{sss}so the build passed` | so the build passed |
| `block` | `the meeting is to day` | the meeting is to day |
| `slow-effortful` | `I would like to go to the garden` | I would like to go to the garden |
| `fluent` | `the plan works for me` | the plan works for me |

A brace glued to a word keeps the word whole, so `{b-b-}but` was said "b-b-but". The four
repetition and prolongation patterns must mark something; a fluent take must mark nothing; a
block or slow take may mark nothing, because what makes it hard is timing rather than words.
`corpus.json` carries `protocolVersion`, and a file from another version is refused.

## What is measured

Each take is aligned against what was meant (`DisfluentSpeechScore`):

| Number | Meaning |
|---|---|
| lost | meant words the clean-up output has no word for; the number that protects a speaker |
| left in | output words with no meant word behind them: disfluency kept, or a word the recogniser made up |
| misheard | meant words written as another word, a rewrite such as a numeral included |
| recogniser WER | the recogniser's transcript against the meant words, before clean-up |

`DisfluentSpeechReport` sums them per pattern and gives the left-in rate over the marked words.
A held sound the recogniser writes as one word ("ssso") reads as misheard, not left in. The
recogniser rows reuse `SpeakerGroupReport`, so their intervals resample speakers, not takes, and
a pattern spoken by one speaker prints "insufficient evidence"
([eval-methodology.md](eval-methodology.md#real-speaker-accent-slices-what-a-group-row-may-claim)).

## Running it

`uttrflow-eval disfluent-speech --corpus <folder>` checks that every take's audio is in its
speaker's subfolder, transcribes each with the shipping recogniser, cleans it as dictation would,
and prints the takes and speakers it read, whether they are enough to decide, then the report.
Takes without audio are skipped. It reads the folder and writes nothing.

## On invented takes

Run through the rules engine with the said text standing in for the recogniser,
`DisfluentSpeechTests` prints: sound repetition 3 of 4 marked words left in, part-word repetition
1 of 2, and no meant word lost in any pattern. Invented text shows the metrics work; it says
nothing about real speakers, and no pass changes on it. The recorded corpus, and the pass
decision read off it, are what this page is for.
