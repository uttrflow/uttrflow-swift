# Word tables as data

Hand-written word lists that the cleanup passes read live in small JSON files under
`Sources/UttrflowCore/Resources/Tables/`, and one loader reads every one of them:
`DataTable` in `Sources/UttrflowCore/Support/DataTable.swift`. A table that needs its own
decoder, its own size check or its own failure behaviour is a second implementation of this
job and is not added.

## Adding a row

Add one object to the table's `rows` array. Nothing else changes: the Swift type that reads
the table builds its sets and dictionaries from the rows when it is first used.

```json
{ "id": "towards", "roles": ["function", "meaningBearing"] }
```

## The file

```json
{ "schema": 1, "rows": [ { "id": "...", ... } ] }
```

| Field | Meaning |
|---|---|
| `schema` | The version of the row shape. The reader states the version it reads; any other is refused. |
| `rows` | The rows, in order. Each has a non-blank `id` that is unique within the file, plus the table's own fields. |

A row's fields are a Swift type conforming to `DataTableRow`, so an unknown enum value, a
missing field or a field of the wrong type refuses the whole file rather than one row.

## Checks, and what a failure does

| Check | Limit | Error |
|---|---|---|
| The file is in the bundle | present | `missing` |
| The file can be read | readable | `unreadable` |
| Size | `DataTableLimits.standard.maxBytes` | `tooLarge` |
| Shape | decodes as the row type | `malformed` |
| Version | equals the reader's `schema` | `unsupportedSchema` |
| Rows | `DataTableLimits.standard.maxRows` | `tooManyRows` |
| Ids | non-blank and unique | `blankID`, `duplicateID` |

A file that fails any check is not used at all. The table keeps the compiled default its
reader passes as `fallback`, records the reason in `DataTable.source`, and logs a fault under
the `tables` category. A shipped table falling back is a packaging defect, so
`DataTableTests` asserts that every shipped table reports `.bundled`.

The word tables pass an empty default. With no words loaded, the passes that read them leave
the speaker's words as spoken, which keeps every word; a default that duplicated the file
would be a second home for the same list.

Tables ship inside the `UttrflowCore` resource bundle, which `Scripts/bundle.sh` seals into
the app with every other resource bundle. Nothing is fetched at run time.

## Tables on the loader

| File | Read by | Rows |
|---|---|---|
| `correction-triggers.json` | `Restatement` | a phrase that announces a spoken correction, its `language`, and the `evidence` it needs before anything is taken back: `alignedHalves`, `alignedHalvesPausedSingleWord`, `restatedNumber`, `pausedRestatedNumber` |
| `function-words.json` | `FunctionWords` | a small word and the lists it belongs to: `function`, `leadsOn`, `meaningBearing`, `determiner` |
| `hindi-words.json` | `HindiWords` | a romanised Hindi spelling, its `classes` (`copula`, `negation`, `postposition`, `conjunction`, `questionWord`, `pronoun`, `possessive`, `verbStem`), the `word` it respells, the pronoun it is a `caseOf`, and whether it is also an `english` content word |
| `kinship-words.json` | `KinshipWords` | a kinship or honorific word said in place of a name, and the `languages` (`en`, `hi`) it is said in |
| `number-words.json` | `NumberWords` | a number word, its value and its rank: `unit`, `teen`, `ten`, `scale` |
| `spoken-commands.json` | `SpokenCommands` | a phrase said as a command, its `action` (`mark`, `layout`, `codeSymbol`), the text it writes, and optionally its `placement`, `requiresLists` and `destinations`; no two rows of one action share a phrase in one destination |
| `technical-lexicon.json` | `TechnicalLexicon` | a technical term's written form and casing, its `spoken` forms, its `category` (`acronym`, `language`, `command`, `tool`, `concept`, `fileFormat`), and optionally `pronunciations` and `destinations` |

## The technical lexicon

Every row is written for this repository and copied from no published list; its licence and
digest are in [data-manifest.md](data-manifest.md). It holds generic technical vocabulary and
the names of widely used open tools and languages, and no person, address or product of a
single vendor. A spoken form is lower-case Latin words separated by single spaces. A term
written or said as an ordinary word (`GeneralVocabulary.isOrdinary`) carries `destinations`,
so it is never offered in prose. `TechnicalLexicon.problems` states these rules, and
`TechnicalLexiconTests` and `TechnicalLexiconOrdinaryTests` fail on any shipped row that
breaks one.

## Testing

`DataTable.decode` takes bytes, so the malformed-input suite and the fuzz test feed it
directly; `DataTable.load` takes a `Bundle`, so the fallback tests point it at a temporary
folder.

```bash
swift test --filter DataTableTests
```
