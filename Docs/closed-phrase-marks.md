# Recogniser marks inside a closed phrase

A speaker who hesitates after "the", "on", "can" or "of" leaves a silence the recogniser can read
as a sentence end, so the raw text says "she put the keys on. The green table". This page holds
how often that happens and what each class of mark is owed.

## Measurement

`uttrflow-eval closed-phrase-marks` speaks 12 invented sentences in 4 `say` voices with a silence
of 0, 400, 800 and 1500 ms after one closed-class word, transcribes each with the shipping
whisperKit model, and counts the recogniser's commas and stops that follow a determiner,
preposition, auxiliary, "and" or "of". Synthetic audio on Apple M5 Pro, 48 GB; recorded clips
were not measured.

| Class | Comma | Stop |
|---|---|---|
| determiner | 0 | 2 |
| preposition | 1 | 9 |
| auxiliary | 1 | 12 |
| and | 0 | 0 |
| of | 0 | 2 |

| Pause ms | Clips | Illegal comma | Illegal stop |
|---|---|---|---|
| 0 | 48 | 0 | 0 |
| 400 | 48 | 2 | 6 |
| 800 | 48 | 0 | 11 |
| 1500 | 48 | 0 | 8 |

27 of 216 recogniser marks (12.5%) fall after a closed-class word. Fluent speech produces none;
every one follows a hesitation of 400 ms or more. The set is built to hesitate in that place, so
12.5% is the rate given such a pause, not the rate in ordinary dictation.

## Decision per class

The local model owns commas and the rules own stops ([cleanup.md](cleanup.md)).

| Class | Stop | Comma |
|---|---|---|
| determiner, preposition, auxiliary, "of" | remove: the phrase is open, so the next word continues the sentence whatever the pause length | remove before the model sees the text; the model places the comma it owns |
| "and" | no case seen; same rule as above when one is | as above |

A mark is never moved across the pause: the pause sits inside the phrase, and its other side is
the word the phrase needs. The removal belongs in the rules' stop owner, keyed on the closed class
of the word before the mark, not on any phrase.
