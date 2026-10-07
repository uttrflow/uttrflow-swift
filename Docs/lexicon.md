# Adding a technical term

The technical lexicon is one data file,
`Sources/UttrflowCore/Resources/Tables/technical-lexicon.json`, read by `TechnicalLexicon`
through the shared loader ([data-tables.md](data-tables.md)). A new term is one row there and
needs no Swift change.

## An entry

```json
{"id": "jq", "category": "command", "spoken": ["j q"]}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | the written form, with its casing: printable Latin-script characters and no spaces; unique in the file |
| `spoken` | yes | one or more ways it is said, each lower-case `a`-`z` and `0`-`9` words separated by single spaces |
| `category` | yes | `acronym`, `language`, `command`, `tool`, `concept`, `fileFormat` or `annotation`; it picks the passes that read the row |
| `destinations` | no | where it applies, for example `["codeEditor", "terminal"]`; left out, it applies everywhere |
| `pronunciations` | no | phoneme spellings; empty until a pronunciation source is added |

## What is rejected

`TechnicalLexicon.problems` holds every rule below, and `TechnicalLexiconTests` and
`TechnicalLexiconOrdinaryTests` fail on any shipped row that breaks one. Each problem names
the row by its `id`. A written form repeated in the file is refused earlier, by the loader
(`DataTableError.duplicateID`), and the whole file then fails to load.

| Problem | Rule |
|---|---|
| `malformedWritten` | the written form is empty, has a space, or has a character outside printable Latin script |
| `unspoken` | the row has no spoken form |
| `malformedSpoken` | a spoken form is not lower-case Latin words separated by single spaces, so Devanagari is rejected |
| `appliesNowhere` | `destinations` is an empty list |
| `ordinaryWithoutDestination` | the written form or a spoken form is an ordinary English word (`GeneralVocabulary.isOrdinary`) and no `destinations` limits it, so it would rewrite everyday prose |
| `duplicateSpoken` | an earlier row of the same category says the same phrase in a destination this row shares |

Two rows may share a phrase across categories: `SSH` (acronym) and `ssh` (command) are both
said `s s h`, and different passes read them.

Beyond what the check can see, a row is written for this repository and copied from no
published list, and names no person and no product of a single vendor.

## Checking a change

```bash
swift test --filter TechnicalLexicon
shasum -a 256 Sources/UttrflowCore/Resources/Tables/technical-lexicon.json
stat -f %z Sources/UttrflowCore/Resources/Tables/technical-lexicon.json
```

The last two print the digest and size for the file's entry in `Resources/DataManifest.json`,
which changes in the same commit ([data-manifest.md](data-manifest.md)). To see the effect on
dictation, run the end-to-end bench for a lexicon change in
[measure-a-change.md](measure-a-change.md) and give before and after in the pull request.

## Worked example

To add `jq`, said "j q", as a command:

1. Add `{"id": "jq", "category": "command", "spoken": ["j q"]}` among the command rows.
2. `jq` is not an ordinary word and "j q" is not one either, so it needs no `destinations`.
3. Run `swift test --filter TechnicalLexicon`; it passes.
4. Update the file's digest and size in `Resources/DataManifest.json`.

## Neighbour report

`LexiconNeighbours.report()` lists, for every row, the ordinary words its written form or a
spoken form sounds like (`GeneralVocabulary.wordsSounding`), and whether a form is itself an
ordinary word. It is computed from the two lists each time and never stored in the file.
`LexiconNeighboursTests` requires one line per row, at least 300 rows, and a `destinations`
limit on every row whose form is ordinary; run it to print the report:

```bash
swift test --filter LexiconNeighbours 2>&1 | grep lexicon-neighbours
```

At 327 rows it reports 19 rows with a neighbour and 8 whose form is an ordinary word. The
report holds no frequency ratio yet: the ordinary-word list is unranked, and a ranked lexicon
waits on the pronunciation-source decision. Neighbours come from the sound key, not from
phoneme distance, for the same reason.

## Coverage on the developer-vocabulary corpus

Cases in the `devvocab` categories of `Scripts/dictation_bench.py` whose term is a row here, by
text, with no audio: commands 8 of 8, tools 8 of 8, acronyms 8 of 8, flags 0 of 8. Flags are
written by the spoken-flag rule, not by lexicon rows. The recognised-audio comparison is the
end-to-end bench in [measure-a-change.md](measure-a-change.md).
