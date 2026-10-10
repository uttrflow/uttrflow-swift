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
| `aside-words.json` | `AsideWords` | an English word said as an aside at the edge of a sentence, and the `positions` (`opening`, `closing`) where `TerminalStopPass` sets it off with a comma in a Hindi sentence |
| `correction-triggers.json` | `Restatement` | a phrase that announces a spoken correction, its `language`, and the `evidence` it needs before anything is taken back: `alignedHalves`, `alignedHalvesPausedSingleWord`, `restatedNumber`, `pausedRestatedNumber` |
| `function-words.json` | `FunctionWords` | a small word and the lists it belongs to: `function`, `leadsOn`, `meaningBearing`, `determiner`, `prose`, `subordinator`, `closingTag` |
| `hindi-words.json` | `HindiWords` | a romanised Hindi spelling, its `classes` (`copula`, `negation`, `postposition`, `conjunction`, `questionWord`, `pronoun`, `possessive`, `verbStem`, `auxiliary`, `particle`, `subject` (opens a fresh clause); a `copula`, `postposition`, `auxiliary` or `particle` is a grammar word the script guard leaves out of its comparison), the `word` it respells, the pronoun it is a `caseOf`, and whether it is also an `english` content word |
| `romanised-variants.json` | `RomanisedVariants` | a romanised Hindi word as it is most often typed (`id`) and the other `variants` people type for it, and `rewritable: false` when a variant is also another word ("main", "to"); `Romaniser.soundKey` maps every spelling of a row to its `id`, and `RomanisedVariants.canonicalised` writes a rewritable row's variants as its `id` in a sentence with two Hindi function words |
| `credential-words.json` | `CredentialWords` | a word that names or surrounds a credential, and the lists it belongs to: `codeSuffix` and `codePrefix` (glued to a short code in a lowercase field name), `netrcValueDirective` |
| `field-kinds.json` | `FieldLabelKinds` | a lowercase phrase from a field's label, the `kind` it names (`name`, `address`, `number`, `date`, `email`, `phone`, `postalCode`, `webAddress`, `title`), its `cue` (`strong`; `weak`, which yields to a strong kind; `joiner`, which makes two kinds name none) and the `languages` (`en`, `hi`) it is written in |
| `html-elements.json` | `HTMLElements` | every element name HTML defines, and how the plain form of copied HTML treats it: `void` (no content or end tag), `block` (starts a new line) |
| `kinship-words.json` | `KinshipWords` | a kinship or honorific word said in place of a name, and the `languages` (`en`, `hi`) it is said in |
| `mark-spacing.json` | `MarkSpacing` | a punctuation mark and the side it goes on (`kind`: `trailing`, `closing`, `opening`, `leading`, `joining`, `standalone`) and, for a `joining` mark only, whether a space sets it apart on each side (`spaced`: the em dash is, a hyphen is glued); a spoken mark row with no `placement` of its own takes it from here, `SpacingPass` moves a stray `trailing` or `closing` mark onto the word before it and spaces every `spaced` mark as a spoken one is written. Straight quotes have no row: their side depends on position |
| `number-cues.json` | `NumberCues` | a word said before or between numbers and the `cues` it gives: `dotted` (dotted digit groups are an address or version), `digitRun` (a run of digits is a code, not a count), `coordinator` (numbers it joins share one form), `range` (a coordinator that joins only a rising pair), `measureLead` and `measureTail` (units that join a two-part measure), `operator` (an arithmetic word written as its `symbol` between numbers, only in a sentence that is all numbers and operators or where every number is a numeral), `designator` (a lone number after it is a numeral, with no digit separator) |
| `number-words.json` | `NumberWords` | a number word, its value and its rank: `unit`, `teen`, `ten`, `scale` |
| `recogniser-words.json` | `RecogniserWords` | a lowercase word the recogniser's tokenizer spells as one token, rows in token id order so a row's position is its frequency rank (`rank(of:)`); derived by `Scripts/derive_recogniser_words.py`, never edited by hand, and read under its own limits (512 KB, 52,000 rows) because it holds the tokenizer's vocabulary rather than a hand-written list ([ordinary-words.md](ordinary-words.md)) |
| `spoken-commands.json` | `SpokenCommands` | a phrase said as a command, its `action` (`mark`, `layout`, `codeSymbol`, `casing`, `flag`, `leadIn`, `replace`, `key`), the text it writes, and optionally its `placement`, `requiresLists`, `destinations`, `languages` (the code languages a `codeSymbol` row is notation in; a row naming languages stays a word where none is known) and `closesItself` (where an opening name said again inside its quotation closes it); no two rows of one action share a phrase in one destination and language |
| `technical-lexicon.json` | `TechnicalLexicon` | a technical term's written form and casing, its `spoken` forms, its `category` (`acronym`, `language`, `command`, `tool`, `concept`, `fileFormat`, `annotation`), and optionally `pronunciations`, `destinations` and `everyday` (a file ending that is also a spoken word) |

## The technical lexicon

Its entry format, what is rejected and how to check a change are in [lexicon.md](lexicon.md).

## Testing

`DataTable.decode` takes bytes, so the malformed-input suite and the fuzz test feed it
directly; `DataTable.load` takes a `Bundle`, so the fallback tests point it at a temporary
folder.

```bash
swift test --filter DataTableTests
```
