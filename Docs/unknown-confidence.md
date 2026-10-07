# What each layer does when a word's confidence is unknown

A `Draft.Word` carries a `confidence` from 0 to 1. A draft built from plain text
(`Draft(text:)`, `Draft(keepingLineBreaks:)`) or from timed words that do not spell the text
gives every word a stand-in of 1, and marks the whole draft with `confidencesAreReal == false`.
A stand-in of 1 is not certainty. Every layer that reads confidence checks the flag first and
states its own choice for the unknown case.

| Layer | Source | Unknown confidence means | Why |
|---|---|---|---|
| Doubtful-word candidates | `Sources/UttrflowAI/Candidates/CandidateSource.swift` (`DoubtfulWords.spans`) | offers nothing | with no doubt signal every span would look certain or every span doubtful; neither is evidence |
| Meaning guard, sound-alike check | `Sources/UttrflowAI/MeaningPreservationGuard.swift` (`confidentHomophoneVerdict`) | accepts the rewrite | the refusal protects a word the recogniser was sure of; an unknown word was not shown to be sure |
| Rules-alone route | `Sources/UttrflowAI/RulesAlone.swift` | sends the text to the model | a doubted word is the model's to resolve, and unknown cannot rule doubt out |
| Dictionary spellings into the transcript | `Sources/UttrflowPipeline/DictationPipeline+Text.swift` (`saying`) | rewrites the text and drops word scores | no score exists to carry forward |
| Explanation export | `Sources/UttrflowAI/DictationExplanation.swift` | prints "not scored" | a stand-in score printed as 1 would read as certainty |

The type-level change, a distinct unknown value with no default so no word can be built
without stating its evidence, and the single policy function that answers this table in code,
are tracked separately; see the pull request that added this page.

## Check

```bash
git grep -n 'confidencesAreReal' -- Sources
```

Every consumer it lists is a row above; a new consumer adds a row.
