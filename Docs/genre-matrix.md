# Genre coverage matrix

Generated from `EvaluationCorpus.genres` and what `RuleBasedTransformer` writes for each case; do not edit by hand.
The genre cases are kept out of `EvaluationCorpus.all` until the meaning guard stops refusing their references.
Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter GenreMatrixTests`.
A genre is covered at 3 cases. Exact is the whole text character for character;
similarity is word agreement and marks is comma and sentence-end agreement, each a mean over the genre.

| Genre | Cases | Spoken words | Rules exact | Rules passed | Similarity | Marks | Covered |
|---|---|---|---|---|---|---|---|
| customer-email | 3 | 195 | 0 of 3 | 3 of 3 | 99% | 50% | yes |
| chat-reply | 3 | 139 | 0 of 3 | 3 of 3 | 100% | 41% | yes |
| meeting-minutes | 3 | 167 | 0 of 3 | 1 of 3 | 97% | 55% | yes |
| status-report | 3 | 160 | 0 of 3 | 2 of 3 | 96% | 50% | yes |
| proposal | 3 | 169 | 0 of 3 | 1 of 3 | 98% | 48% | yes |
| apology | 3 | 169 | 0 of 3 | 3 of 3 | 98% | 48% | yes |
| cover-letter | 3 | 191 | 0 of 3 | 3 of 3 | 100% | 45% | yes |
| invitation | 3 | 176 | 0 of 3 | 3 of 3 | 98% | 72% | yes |
| shopping-list | 3 | 149 | 0 of 3 | 2 of 3 | 96% | 50% | yes |
| recipe | 3 | 173 | 0 of 3 | 3 of 3 | 98% | 48% | yes |
| travel-plan | 3 | 176 | 0 of 3 | 3 of 3 | 98% | 61% | yes |
| clinic-note | 3 | 158 | 0 of 3 | 1 of 3 | 96% | 67% | yes |
| legal-clause | 3 | 164 | 0 of 3 | 2 of 3 | 98% | 50% | yes |
| essay-paragraph | 3 | 205 | 0 of 3 | 2 of 3 | 99% | 50% | yes |
| poem | 3 | 138 | 0 of 3 | 3 of 3 | 100% | 0% | yes |
| product-description | 3 | 158 | 0 of 3 | 2 of 3 | 99% | 67% | yes |
| social-post | 3 | 133 | 0 of 3 | 1 of 3 | 95% | 50% | yes |
| announcement | 3 | 147 | 0 of 3 | 3 of 3 | 99% | 49% | yes |
| corrected-reply | 3 | 128 | 0 of 3 | 2 of 3 | 95% | 48% | yes |
| hinglish-technical | 3 | 133 | 0 of 3 | 2 of 3 | 99% | 67% | yes |

Genres at 0% exact on the rules path: `customer-email`, `chat-reply`, `meeting-minutes`, `status-report`, `proposal`, `apology`, `cover-letter`, `invitation`, `shopping-list`, `recipe`, `travel-plan`, `clinic-note`, `legal-clause`, `essay-paragraph`, `poem`, `product-description`, `social-post`, `announcement`, `corrected-reply`, `hinglish-technical`.
