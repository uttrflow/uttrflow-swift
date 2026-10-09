# Destination coverage matrix

Generated from `EvaluationCorpus.all`; do not edit by hand.
Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter DestinationMatrixTests`.
A case's cell is its own destination and the field kind `DestinationFormatter.fieldKind(of:)` reads
from its context. A cell has behaviour of its own when the formatter writes that field differently
from the destination's primary field, and then needs 8 cases; any other is listed as none shipped.

| Destination | primary | one-line | search | recipient | subject |
|---|---|---|---|---|---|
| document | 149 | 8 | 8 | 0, none shipped | 0, none shipped |
| spreadsheet | 8 | 0, none shipped | 8 | 0, none shipped | 0, none shipped |
| sqlEditor | 9 | 8 | 8 | 0, none shipped | 0, none shipped |
| codeEditor | 24 | 8 | 8 | 0, none shipped | 0, none shipped |
| terminal | 14 | 0, none shipped | 8 | 0, none shipped | 0, none shipped |
| messaging | 78 | 8 | 8 | 0, none shipped | 0, none shipped |
| email | 15 | 8 | 8 | 8 | 8 |
| plain | 691 | 10 | 9 | 0, none shipped | 0, none shipped |

Cells under the floor: none.
