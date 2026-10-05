# Learned state: one evidence ledger

Everything the app infers about this user is a fact with a reason behind it. Today each feature
keeps its own counter in its own file, so "used" means a different thing in each, and nothing
can decay because a counter has no dates. This page fixes the shape every inferred fact takes
from here on, maps each existing store onto it, and records what the prototype projection
measured. Rule: no new stored counter is added anywhere; a new fact is a new evidence kind.

## Two kinds of state

**Declarations** are what the user stated outright: a word typed into the dictionary, a snippet,
a refusal, a setting. They are exact, never decay, and are edited in place.

**Evidence** is what the app observed. It is a list of rows, never a counter:

| Field | Meaning |
|---|---|
| `kind` | `use`, `revert`, `restore`, `sighting`, … (closed enum) |
| `subject` | The key the row is about: a dictionary entry id, a snippet id, a spelling key |
| `weight` | Signed integer; `+1` for an ordinary observation |
| `day` | Day number, not a timestamp, so rows carry no time of day |
| `provenance` | Which path produced it: `dictation`, `undo`, `user`, `migration` |

Rows are appended and periodically compacted: rows of one `(kind, subject)` older than the
compaction horizon fold into one row whose weight is their sum and whose day is the newest
folded day. Compaction never changes a projection that ignores days, which is what lets the
migration below start from one folded row.

**Projections** are pure functions of declarations and evidence, computed on read:
`used`, `confirmed`, `vetoed`, `stale`, domain mix and pair features. Only a projection is
shown or acted on; nothing stores its result.

## `restore` is a marker, not a subtraction

`PersonalDictionaryStore.restore` sets `timesReverted` to 0 and keeps uses. A ledger cannot
delete rows to do that without losing history, so a `restore` row means "ignore `revert` rows
for this subject on or before me". The projection honours it; the prototype test pins it.

## Inventory: a decision per file

| Store | Holds | Decision |
|---|---|---|
| `dictionary.v1.json` | Entries (declaration) plus `timesUsed`, `timesReverted` (evidence) | **Move** the counters to the ledger; the entry keeps word, pronunciation, origin, `firstSeen`. `timesUsed`/`timesReverted` stop being stored fields once the ledger ships; `netUses` and `isTrustworthy` become projections |
| `dictionary.seeded.json` | Spellings already offered from the shipped list | **Keep** as a declaration: it is a fact about this install, not evidence, and never decays |
| `dictionary.refused.json` | Words the user deleted | **Keep** as a declaration (a veto the user made); the pending sighting counts in `SightingLedger` move to the ledger as `sighting` rows |
| `snippets.v1.json` | Snippets plus `timesUsed`, `lastUsed` | **Move** both to `use` rows; `lastUsed` is the newest `use` day, so it stops being stored |
| `history.v1.json` | What was dictated | **Keep** separate: it is content, not inferred fact, and has its own retention clock |
| `predict.v1.sqlite` | Prediction corpus | **Keep** separate (volume and query shape differ); it shares consent and reset with the ledger |
| Planned `PersonaProfile` | Inferred preferences | **Do not create** as its own store: it is a set of projections over this ledger |

## Migration of `dictionary.v1.json` counters

Each entry with `timesUsed = u`, `timesReverted = r` becomes at most two rows on the day of
migration, provenance `migration`: `(use, id, +u)` and `(revert, id, +r)`, a zero weight
writing no row. Because the fold is a sum, every day-independent projection is identical
before and after. Day-dependent projections (`stale`, decay) treat migrated rows as dated on
the migration day, which is the honest answer: the file never recorded when.

## Measured

`Tests/UttrflowDictionaryTests/EvidenceProjectionTests.swift` holds the prototype ledger,
the migration and two projections, and checks them against `DictionaryEntry` itself:

- for every `(timesUsed, timesReverted)` pair from 0 to 12 each, migrated rows project the same
  `netUses` and `isTrustworthy` as the entry;
- replaying a sequence of uses, undos and a restore through `PersonalDictionaryStore` and
  through the ledger gives the same `netUses` and `isTrustworthy` after every step;
- compacting the ledger changes neither projection.

## Where the ledger lives

`EvidenceLedgerStore` keeps every row in one `EncryptedStore` file, `evidence.v1.json`
(`LocalStoreEntry.evidenceLedger`), with `schemaVersion` 1; a newer file is left unread and
unwritten. It exists only when the app has encryption, so it is never written in plain text.
It sends nothing anywhere and logs nothing about its rows.

- **Retention**: the same promise as History. Every read and append takes the History
  `RetentionWindow`; a row is measured from the first instant of its day, so it never outlives
  the window, and a clock too far ahead to be believed only hides a row rather than deleting it.
  The hourly retention sweep and every Settings count apply it to the disk.
- **Reset**: "Reset everything" deletes the file. "Forget learned words" keeps it, because
  rows also count uses of words the user added.

## Style signals

`StyleSignals` writes five style kinds per inserted, non-secure dictation, with the
`Destination` as the subject and no word of the text: `styleMessage` (+1), `styleWords`
(word count), `styleSentences` (runs closed by `.`, `?` or `!` before a space or the end, plus
an unclosed tail), and, for a dictation of at most 12 words, `styleShortMessage` (+1) and
`styleClosingStop` (+1 when it ends with `.`). The projection per destination is
`meanSentenceLength` = words / sentences and `closingStopRate` = closing stops / short
dictations. No contraction rate is kept: acting on one would rewrite the user's words.

## Spelling preferences

`SpellingPreferences` writes one `spellingPreference` row per word of an edit inside dictated
text whose two sides are spellings of one listed Hindi word (`thik` to `theek`), with the
subject `heard>meant` in lower case; a pair that is not two spellings of one word, or an edit
that changes the word count, writes nothing. The projection prefers `meant` once its rows fall
on at least 3 separate days and outweigh edits the other way, so a lone edit is inert. Deleting
the preference writes `spellingPreferenceCleared`, which hides every earlier row for the pair in
both directions. Applying the projection waits on the canonical-spelling step.

## Still open

The downgrade rule for the ledger's own file belongs to the store compatibility contract. The
decay curve and compaction horizon need measurement on real use before a number is written here.
