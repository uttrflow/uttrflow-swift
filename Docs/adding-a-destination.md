# Adding a destination

A destination is the kind of place the words are going, and it decides the formatting. Most
changes are smaller than a destination: a new app is a row, a new decision is a field. This page
says which one you need, then the steps for a new destination, with `.spreadsheet` as the worked
example. The table of decisions is [cleanup-design.md](cleanup-design.md); the finer seam the
destination grows into is [adapters.md](adapters.md).

## Which change you need

| You want | Change | Where |
|---|---|---|
| an app to format like an existing kind | a row | `DestinationRules.standard` in `Sources/UttrflowCore/Models/DestinationRules.swift`, with an `AppKind` |
| one app to differ from its kind on the final stop only | the row's `terminalStop` | the same row |
| a place whose words follow different decisions | a destination | the steps below |
| a decision that needs the grammar of the text (SQL, a shell line) | an adapter | [adapters.md](adapters.md); not a new branch on the destination |

A destination is never keyed by `if destination ==` in a pass or in the pipeline: what differs is
a value in the formatter or a policy a pass is constructed with.

## The steps

1. **Write the success check first.** For example
   `swift test --filter DestinationFormatterTests` fails, then passes.
2. **Add the case** to `Destination` in `Sources/UttrflowCore/Models/Destination.swift`, with a
   one-line comment naming the kind of app, as `.spreadsheet` does ("one cell").
3. **Add the kind of app** to `AppKind` in `Sources/UttrflowCore/Models/AppKind.swift` and map it
   in `AppKind.destination`, unless an existing kind already names it. A rule built from a kind
   cannot disagree with its caption.
4. **Give it its decisions** in `DestinationFormatter.registry` in
   `Sources/UttrflowCore/Models/DestinationFormatter.swift`: first word, final stop, layout,
   grammar, numbers, digit grouping, prompt block and consequence. Every field is a decision, not
   code. `.spreadsheet` is `.asSpoken`, `.never`, `.singleLine`, `.asSpoken`, `.always`. A
   destination the registry lacks falls back to plain text's formatter silently, which is why the
   test in step 9 exists.
5. **Declare its consequence**: what a typed Return does there (`Consequence` in
   `Sources/UttrflowCore/Adapters/Consequence.swift`). A place where Return sends or runs the text
   never gets paragraphs or lists.
6. **Write its prompt block** in `Sources/UttrflowAI/PromptBlocks.swift`: a heading, two to four
   rule lines, and at most two worked examples, only where its layout or final stop differs from
   the contract's examples. Add it to `PromptBlocks.standard`. An example that says a command
   from `spoken-commands.json` is `WorkedExample.notation`, whose cleaned side the place's rules
   write, so the table stays its one source.
7. **Route apps to it**: add rows to `DestinationRules.standard` by bundle prefix, window-title
   fragment or whole name word. The longest bundle prefix wins, so a broad vendor prefix does not
   need excluding.
8. **Let the user choose it.** The settings list of destinations is built from
   `Destination.allCases`; check the caption it shows in `Sources/UttrflowUX/`.
9. **Pin it in tests.** `DestinationFormatterTests` (every destination has a value and a
   consequence), `DestinationClassifierTests` (each new row resolves), and `PromptBuilderTests`
   (every destination has a block) fail until steps 4 to 7 are done. Add the expected values;
   never loosen the `allCases` checks.
10. **Cover it in the corpus.** Add cases for the destination to the category files under
    `Sources/UttrflowEval/Resources/Corpus/` tagged with the `per-destination` class, and
    regenerate [formatting-matrix.md](formatting-matrix.md) with
    `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter FormattingMatrixTests`. A class counts as covered
    at 5 tagged cases.
11. **Stay inside the budget.** A destination adds no stage: its passes run inside
    `StageTimeout.transformation` ([pipeline.md](pipeline.md)).
12. **Update the pages** that list destinations: the decision table in
    [cleanup-design.md](cleanup-design.md) and the case count in [adapters.md](adapters.md).
13. **Measure.** Run `make bakeoff` on `origin/main` and on your branch and put the before and
    after in the pull request ([measure-a-change.md](measure-a-change.md)).
14. **Run the checks**: the three suites in step 9, `swift test --filter FormattingMatrixTests`,
    `make lint`, `make comment-audit`, `make docs-audit`, and `make verify` before you push.
