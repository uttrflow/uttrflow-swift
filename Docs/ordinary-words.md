# What counts as an ordinary word

`GeneralVocabulary` decides which words a general recogniser already spells, so the dictionary
does not learn them, the ordinary-word veto refuses them and sound-alike readings come from them.
This page scores three definitions of that set against a labelled fixture.

## The fixture

`Tests/Fixtures/ordinary-words/labelled.tsv`: 300 words, each labelled `ordinary` or `personal`,
in four groups: everyday English (103), programmer vocabulary (56), romanised Hindi (49) and
invented personal terms (92). It holds words only, and every personal term is invented.

## The definitions

1. The hand list in `GeneralVocabulary.swift`.
2. The recogniser tokenizer's cost: the number of byte-level BPE tokens for the word with a
   leading space, read from the `tokenizer.json` the speech model already installs.
3. The system word list at `/usr/share/dict/words` (Webster's Second International, public
   domain), standing in for a published list that needs no download.

## Results

```bash
python3 Scripts/ordinary_word_probe.py --tokenizer <model folder>/tokenizer.json
```

Measured with the large-v3 turbo tokenizer:

| definition | precision | recall | english correct | hindi correct | personal correct | programmer correct |
|---|---|---|---|---|---|---|
| hand list | 1.000 | 0.269 | 14/103 | 41/49 | 92/92 | 1/56 |
| tokenizer, 1 token | 1.000 | 0.721 | 103/103 | 5/49 | 92/92 | 42/56 |
| tokenizer, at most 2 tokens | 0.892 | 0.913 | 103/103 | 36/49 | 69/92 | 51/56 |
| system word list | 0.993 | 0.721 | 100/103 | 8/49 | 91/92 | 42/56 |
| tokenizer, 1 token, or the Hinglish list | 1.000 | 0.899 | 103/103 | 42/49 | 92/92 | 42/56 |

## Verdict

The tokenizer's cost wins: one token keeps precision at 1.000 (no invented term is called
ordinary) and lifts recall from 0.269 to 0.721, with every everyday English word and 42 of 56
programmer words. Two tokens buys recall at the cost of 23 invented terms, so one token is the
line. The system word list matches the tokenizer's recall with lower precision and adds a file
the app does not ship, so it loses.

The tokenizer is English-centred and splits romanised Hindi, so the Hinglish list stays: it is
also what `isHindiSpellingPreference` reads. One token or the Hinglish list scores 1.000
precision and 0.899 recall. The English hand list is the losing definition.

Limits: the fixture is 300 words labelled by one reader; programmer words the tokenizer splits
(`rebase`, `webhook`, `refactor`) still need the dictionary or a context hint.
