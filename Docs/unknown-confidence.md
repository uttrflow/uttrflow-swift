# What each layer does when a word's confidence is unknown

A `Draft.Word` carries `evidence`: `.score(x)` with the recogniser's confidence from 0 to 1, or
`.unknown`. Neither initialiser has a default, so no word is built without stating which. A
draft built from plain text (`Draft(text:)`, `Draft(keepingLineBreaks:)`), from timed words that
do not spell the text, or a word a pass inserts, carries `.unknown`. `confidencesAreReal` is
derived: true when any word carries a score. `Word.confidence` reads 1 for an unknown word so a
threshold never doubts it; that 1 is not certainty, and every layer below checks the flag first
and states its own choice for the unknown case.

| Layer | Source | Unknown confidence means | Why |
|---|---|---|---|
| Doubtful-word candidates | `Sources/UttrflowAI/Candidates/CandidateSource.swift` (`DoubtfulWords.spans`) | offers nothing | with no doubt signal every span would look certain or every span doubtful; neither is evidence |
| Meaning guard, sound-alike check | `Sources/UttrflowAI/MeaningPreservationGuard.swift` (`confidentHomophoneVerdict`) | accepts the rewrite | the refusal protects a word the recogniser was sure of; an unknown word was not shown to be sure |
| Rules-alone route | `Sources/UttrflowAI/RulesAlone.swift` | sends the text to the model | a doubted word is the model's to resolve, and unknown cannot rule doubt out |
| Dictionary spellings into the transcript | `Sources/UttrflowPipeline/DictationPipeline+Text.swift` (`saying`) | rewrites the text and drops word scores | no score exists to carry forward |
| Explanation export | `Sources/UttrflowAI/DictationExplanation.swift` | prints "not scored" | a stand-in score printed as 1 would read as certainty |

`EvidencePolicy.unscored(_:in:)` in `Sources/UttrflowAI/EvidencePolicy.swift` answers this
table in code: each consumer names its layer and acts on the choice it returns, and
`EvidencePolicyTests` pins one choice per row. A changed choice is made there, on measured
grounds, in its own pull request.

## Check

```bash
git grep -n 'confidencesAreReal' -- Sources
```

Only `Draft.swift` and `EvidencePolicy.swift` are listed; a new consumer adds a `Layer` case
and a row above.
