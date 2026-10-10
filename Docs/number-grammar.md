# Number grammar by semiotic class

Generated from the `semiotic` tags in `EvaluationCorpus` run through the rules engine; do not edit by hand.
Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter NumberGrammarScoreTests`.
Scored without folding number words: exact match, value errors (the numbers read differ),
and false conversions (numerals beyond the reference's). Every class counts under the `numbers` matrix row.

| Class | Policy | Cases | Exact | Value errors | False conversions |
|---|---|---|---|---|---|
| cardinal | from-ten | 1 | 1 | 0 | 0 |
| cardinal | always | 0 | 0 | 0 | 0 |
| ordinal | from-ten | 0 | 0 | 0 | 0 |
| ordinal | always | 0 | 0 | 0 | 0 |
| decimal | from-ten | 0 | 0 | 0 | 0 |
| decimal | always | 0 | 0 | 0 | 0 |
| fraction | from-ten | 0 | 0 | 0 | 0 |
| fraction | always | 0 | 0 | 0 | 0 |
| money | from-ten | 1 | 1 | 0 | 0 |
| money | always | 0 | 0 | 0 | 0 |
| measure | from-ten | 1 | 1 | 0 | 0 |
| measure | always | 0 | 0 | 0 | 0 |
| date | from-ten | 0 | 0 | 0 | 0 |
| date | always | 0 | 0 | 0 | 0 |
| time | from-ten | 1 | 1 | 0 | 0 |
| time | always | 0 | 0 | 0 | 0 |
| telephone | from-ten | 0 | 0 | 0 | 0 |
| telephone | always | 0 | 0 | 0 | 0 |
| electronic | from-ten | 0 | 0 | 0 | 0 |
| electronic | always | 0 | 0 | 0 | 0 |
| stays-words | from-ten | 1 | 1 | 0 | 0 |
| stays-words | always | 0 | 0 | 0 | 0 |
