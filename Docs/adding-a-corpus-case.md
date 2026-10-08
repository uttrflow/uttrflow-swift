# Adding a corpus case

A clean-up case is one JSON object in a file under `Sources/UttrflowEval/Resources/Corpus/`; adding
one needs no Swift change. This page is the schema, how to choose a file and an origin, the checks
the case must pass, and the command that scores it alone. What the corpus measures and how a case
is scored is [bakeoff.md](bakeoff.md); why each provenance field exists is
[bakeoff-method.md](bakeoff-method.md#provenance-and-the-held-out-split).

## Before you start

A case states one behaviour: these words, said here, come out as this. An accuracy fix adds the
case that fails before the fix and passes after it ([CONTRIBUTING.md](../CONTRIBUTING.md)). If an
existing case already states the behaviour, the fix needs no new case.

## Choose the file

The file name is the category, from `EvaluationCase.Category` in
`Sources/UttrflowEval/EvaluationCase.swift`:

| File | What its cases are |
|---|---|
| `everyday.json` | everyday speech: fillers, false starts, missing punctuation |
| `technical.json` | names, code, SQL and product terms that must survive unchanged |
| `technical.codeToken.json` | letter-and-digit codes said into a notes document |
| `multilingual.json` | languages Apple's model does not cover, Hindi romanised |
| `contextual.json` | the same words coming out differently under a different window ([eval-context-cases.md](eval-context-cases.md)) |
| `grammar.json` | grammar slips a formatter may repair, and dialect that must stay |
| `secondLanguage.json` | second-language grammar written down as spoken, never repaired |
| `oneLineField.json` | an entry into a one-line field of no known purpose |
| `bareLiteral.json` | a dictation that is only an address or a path |
| `commandInput.json` | a query or command for a launcher panel |
| `longInput.json` | a dictation of three hundred words or more |
| `dictionary.json` | a dictation holding words from the user's dictionary |
| `webDestination.json` | a dictation into a page in a browser: web mail, web chat or a search field |
| `notARequest.hostileSelectedText.json`, `notARequest.hostileWindowTitle.json` | ordinary dictation beside a hostile instruction on screen ([ai-context-line.md](ai-context-line.md)) |

`technical.abstention.json` is no part of the scored corpus; `AbstentionCorpusTests` runs it
through the rules ([bakeoff.md](bakeoff.md#the-corpus)). The request-shaped `notARequest` cases are
built in `Sources/UttrflowEval/RequestCorpus.swift`, not read from a file. A new file name is a new
list in `EvaluationCorpus`, which is a Swift change.

`everyday`, `notARequest`, `secondLanguage`, `oneLineField`, `longInput`, `bareLiteral`,
`commandInput`, `dictionary` and `webDestination` hold their references to a transcript: the
spoken words in order, some removed, with only marks, capitals and numerals added, and spaces
closed between words written as one.
`TranscriptReferenceTests` fails on any other reference there
([product.md](agents/product.md#dictation-and-clean-up)).

## Write the object

Append it to the file's array. `id`, `spoken` and `expected` are required; every other key is
optional and takes the default shown.

| Key | Meaning | Default |
|---|---|---|
| `id` | unique across every file; lower case words joined by `-` | required |
| `spoken` | the raw transcript, as a recogniser writes it | required |
| `expected` | a good result, in Latin letters | required |
| `note` | why the case exists, for the reader; never scored | none |
| `language` | the speaker's language code, such as `hi` | `en` |
| `origin` | `authored`, `reportRewrite` or `synthetic` | `authored` |
| `addedFor` | the issue number the case was added for | none |
| `mustKeep` | words that must survive; each must be in `expected` as the scorer reads it | `[]` |
| `mustNotAdd` | words that must not appear | `[]` |
| `context` | what was on screen: `applicationName`, `bundleIdentifier`, `documentName`, `pageAddress`, `selectedText`, `precedingText`, `followingText`, `accessibilityRole`, `isMultiline`, `fieldLabel` | nothing known |
| `destination` | a `Destination` raw value, such as `document`, `messaging` or `codeEditor` | `plain` |
| `mustBeginWith`, `mustEndWith` | exactly how the output must begin or end | none |
| `expectedExact` | the one written form a structured output must take, in Latin letters | none |
| `doubtful` | spoken runs the recogniser was unsure of | `[]` |
| `pausedAfter` | positions of the spoken words a sentence-length pause follows | `[]` |
| `minimumSentences` | the fewest sentences the output must close | none |
| `dictionary` | the user's dictionary words, handed to the engine as the request's vocabulary | `[]` |
| `classes` | `FormattingClass` raw values the case exercises | `[]` |

`origin` says where the text came from. `authored` is written from scratch to state a behaviour.
`reportRewrite` is rebuilt from a reported failure, keeping its shape with every value replaced.
`synthetic` is generated from a template or a rule.

**Every value is invented.** No name, address, email, number, document title or sentence is copied
from a real person, a real report or a screen you can see, whatever the origin. Use `example.com`
and its subdomains, invented street names and invented people. `make pii-audit` scans the corpus
files like any other tracked file.

The split is not chosen: `CorpusSplit` holds out one id in five by a digest of the id alone, so a
case keeps its split for as long as it keeps its id. Never read a held-out case's text while tuning
([bakeoff-method.md](bakeoff-method.md#which-score-to-look-at)).

A formatting class counts as covered at 5 tagged cases ([formatting-matrix.md](formatting-matrix.md));
after tagging, regenerate that page with
`UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter FormattingMatrixTests`, never by hand.

## Check it

1. `swift test --filter CorpusFileTests` loads every file through `CorpusFile`, the one validator.
   It fails naming the case on a duplicate id, a `mustKeep` word missing from `expected`, a
   reference outside Latin letters, an unknown key, a bad language or an empty required field.
2. `python3 Scripts/data_manifest.py` fails because the file's digest changed, and prints the
   `bytes` and `sha256` to write into its entry in `Resources/DataManifest.json`
   ([data-manifest.md](data-manifest.md)).
3. `make docs-audit` fails until the category count in the corpus sentence of
   [bakeoff.md](bakeoff.md#the-corpus) is raised by one, with the total.
4. Adding a case passes `make corpus-edit-audit`. Changing or removing an existing one fails it
   unless the branch adds a line `<case id> <reason>` to `Scripts/corpus_edits.txt`.
5. `make verify` runs all of these, and the suites that hold the corpus to its rules: transcript
   references, the held-out split, no overlap with the prompt, and the evidence suites in
   [bakeoff-method.md](bakeoff-method.md#evidence-the-corpus-must-hold).

## Score it alone

```bash
make bakeoff ARGS="--case <id> --baselines-only"
```

This scores the one case with the rules, Apple's model and the shipping router, and prints why each
failed. Drop `--baselines-only` to score the local models too, which downloads them. A one-case run
is not stored, so it never replaces a whole run. To show that a fix needs the case, run it on
`origin/main` and on the branch, and put both results in the pull request.
