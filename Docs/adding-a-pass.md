# Adding a cleaning pass

A new deterministic cleaning is a new `CleaningPass` in a list, never a new branch in the
pipeline. This page is the steps, with `ContractionsPass` as the worked example: it is the
smallest pass in the tree, needs no model and no destination, and is switchable in settings. The
design behind the seam is [cleanup-design.md](cleanup-design.md); what a pass may do to the words
is [cleanup.md](cleanup.md).

## Before you start

A pass answers one question from the words alone, or from a policy it is constructed with. If
the question needs the destination's grammar (SQL, a shell line, a formula), it belongs to an
adapter instead: read [adapters.md](adapters.md) and [adding-a-destination.md](adding-a-destination.md).
If an existing pass already answers the question, extend that pass; a second pass doing the same
job is a defect ([code-quality.md](agents/code-quality.md#fixing-a-defect)).

## The steps

1. **Write the success check first.** For example
   `swift test --filter <Name>PassTests` fails, then passes.
2. **Name the pass.** Add a `PassID` in `Sources/UttrflowCore/Cleaning/PassID.swift` with a
   one-line comment saying what it takes out or writes. Example: `PassID.contractions`. The
   identifier is what every word the pass touches is recorded under, so it never changes once
   shipped.
3. **Choose its scope.** Adopt `PieceCleaningPass` when one piece alone answers the question, or
   `WholeTextCleaningPass` when it needs the joined message (casing, the final stop). Both are in
   `Sources/UttrflowCore/Cleaning/CleaningPass.swift`; the compiler then keeps the pass out of the
   wrong list. `ContractionsPass` is a piece pass.
4. **Declare what it may remove.** Leave `removes` at its default (`.conversion`) when the pass
   only turns words into what it writes, as `ContractionsPass` does. A pass that deletes words
   declares `.sound`, `.repetition` or `.retraction`, and the meaning guard holds each removal to
   that grant ([mutation-guard.md](mutation-guard.md)).
5. **Write the pass** in `Sources/UttrflowAI/Passes/<Name>Pass.swift`: a `struct`, constructed
   with whatever it reads, whose `apply(_:)` is a pure function of the `Draft`. Change words only
   through `Draft`'s editing calls with `by: Self.id`, so the record says which pass did it. A word
   is the same word by its key, never by its spelling shape
   ([code-quality.md](agents/code-quality.md)). One-line `///` comments only.
6. **Write its tests** in `Tests/UttrflowAITests/Passes/<Name>PassTests.swift`, in the shape of
   `ContractionsPassTests.swift`: a `@Suite` named after the pass, parameterised `@Test`s of input
   and expected text through `cleaned(_:by:)` from `PassSupport.swift`, and a separate test for
   each word the pass must leave alone. The leave-alone cases are the ones that stop it becoming a
   rewrite.
7. **Register it once**, in `Sources/UttrflowAI/Passes/CleaningPipeline+Standard.swift`: a piece
   pass in `piece(...)`, a whole-text pass in `message(...)`. Its position is the only ordering
   decision; when it depends on another pass, say so in a one-line comment above it, as the
   `SpokenPunctuationPass` line does.
8. **Pin the order.** Add the identifier where it runs in the expected list in
   `Tests/UttrflowAITests/Passes/StandardPipelineTests.swift`; that test fails until you do.
9. **Decide whether the user may switch it off.** If yes, add a `CleaningStep` to
   `CleaningSteps.offered` in `Sources/UttrflowCore/Cleaning/CleaningSteps.swift` with a plain
   name, a one-line detail and an invented example sentence; filter it with `steps.runs` where it
   is registered. `ContractionsPass` is offered as "Contractions". A pass not offered always runs.
10. **Cover its formatting class in the corpus.** Tag cases in
    `Sources/UttrflowEval/EvaluationCorpus.swift` with the class the pass serves. A class counts
    as covered at 5 tagged cases ([formatting-matrix.md](formatting-matrix.md)); regenerate that
    page with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter FormattingMatrixTests`, never by hand.
    Corpus sentences may not appear in the prompt ([bakeoff.md](bakeoff.md)).
11. **Stay inside the budget.** Every pass runs inside `StageTimeout.transformation`
    ([pipeline.md](pipeline.md)); no pass declares its own budget yet. A pass that scans the draft
    more than once per word says why in the pull request with a timing.
12. **Update the design table.** Add a row to the pass table in
    [cleanup-design.md](cleanup-design.md), section 3.
13. **Measure.** Run `make bakeoff` on `origin/main` and on your branch, and put the before and
    after in the pull request ([measure-a-change.md](measure-a-change.md)).
14. **Run the checks**: `swift test --filter <Name>PassTests`, `swift test --filter
    StandardPipelineTests`, `make lint`, `make comment-audit`, `make match-audit`, and
    `make verify` before you push.

## What a no-op pass touches

A pass that changes nothing still touches steps 2, 5, 6, 7 and 8: `PassID.swift`, the new pass
file, its test file, `CleaningPipeline+Standard.swift` and `StandardPipelineTests.swift`. Steps 9
to 12 are added when the pass does real work.
