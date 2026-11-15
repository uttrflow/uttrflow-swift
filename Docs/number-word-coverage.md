# Number-word coverage against CLDR

`Sources/UttrflowCore/Resources/Tables/cldr-en-spellout.json` holds the English cardinal and
ordinal words of one pinned Unicode CLDR release (`common/rbnf/en.xml`, release-46, Unicode-3.0
licence), with the release and the producing script in its [manifest](data-manifest.md) entry.
`Scripts/cldr_extract.py` derives it:

```bash
curl -O https://raw.githubusercontent.com/unicode-org/cldr/release-46/common/rbnf/en.xml
python3 Scripts/cldr_extract.py en.xml release-46 > Sources/UttrflowCore/Resources/Tables/cldr-en-spellout.json
python3 Scripts/data_manifest.py --update
```

`CLDRSpellout.coverage` compares it with `NumberWords` (the number-word table and the ordinals);
`CLDRSpelloutTests` fails when either list below changes.

## What the hand tables miss

| CLDR word | Value | Decision |
|---|---|---|
| `quadrillion` | 10^15 | add a row to `number-words.json` when a destination needs it; no dictation says it |
| `hundredth`, `thousandth`, `millionth`, `billionth`, `trillionth`, `quadrillionth` | scales | kept out: an ordinal scale is read as a fraction or a position, and which one is a decision for the number policy, not a lexicon |
| `zeroth` | 0 | kept out: no date, list or floor is numbered from "zeroth" |

## What only the hand tables hold

| Word | Why CLDR's English lacks it |
|---|---|
| `lakh`, `lac`, `crore` | Indian English scales, which the CLDR `en` locale does not list; they stay in `number-words.json` |

Not covered: currency names, units and month names, which this extract does not yet read.
