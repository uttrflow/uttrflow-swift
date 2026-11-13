# Code language detection

`CodeLanguage.detect(_:)` in `Sources/UttrflowCore/Models/CodeLanguage.swift` labels a code clip
when the clip alone says which language it is. The label decorates the panel row's language chip
and the preview, and chooses which formatter may be offered
([`clipboard-reindent.md`](clipboard-reindent.md#running-a-formatter)). A wrong label is a small
lie the user discounts on every scan, so `nil` is the usual answer.

`CodeShapes.matches(_:)` checks whether clipboard text has enough source structure to treat it as code.
It recognizes HTML, Markdown, consecutive YAML/TOML pairs and standalone statements. Known diagnostics
and unstructured prose stay text; language detection runs afterward.

| Value | Constant | Why |
| --- | --- | --- |
| 3 points | `bar` | one near-unique marker plus corroboration, never a single token |
| 2 points | `margin` | the winner leads the runner-up by the weight of one near-unique signal |
| 4,000 characters | `windowLength` | about eighty lines; a minified bundle repeats itself, and ninety regular expressions over half a megabyte would stall ⌘C |

## Order

1. Fewer than three characters after trimming: `nil`. Two characters cannot carry two
   independent signals.
2. Any ```` ``` ```` fence: `nil`.
3. Valid JSON with an object or array at the top: `json`. `{ retries: 3 }` fails on its
   unquoted key and falls through; a quoted-key object copied on its own came out of an API
   response far more often than out of a source file.

The rest reads only the first `windowLength` characters.

4. A shebang names its interpreter outright: Python, Ruby, a JavaScript runtime, Swift or a
   shell. Any other interpreter (`perl`, `awk`, `tclsh`) falls through rather than being forced
   into `shell`.
5. A SQL statement: no full stop at the end, and no English articles (`the`, `a`, `your`,
   `please`, `should`…) unless the statement corroborates itself (a trailing semicolon,
   `SELECT *`, a second clause keyword). "Select an item from the list below" satisfies every
   clause-shape test you can write. `FROM` may stand on a later line than `SELECT`, as formatted
   SQL puts each clause on its own line; the two are read within 400 characters of each other.
6. Scoring.

## Scoring

Strong signals (near-unique to one language: `\(…)`, `module.exports`, `elsif`, `:=`) score 2;
supporting signals (consistent with a language: `nil`, `->`, a trailing semicolon) score 1.
Distinct signals count, not occurrences, so `console.log` forty times is one signal.

- **Bar: 3.** One near-unique marker plus something corroborating, or three corroborating ones.
  What three rules out is the single token: `->` is Rust, Python, PHP and C++; `let` is Swift,
  JavaScript and Rust; `end` is Ruby and Lua; `func` is Swift and Go.
- **Margin: 2.** The winner must lead the runner-up by the weight of a near-unique signal. This
  protects Swift from TypeScript, which share `let`, `import`, a function keyword and `:`
  annotations. A tie names a family, not a language.

Go and Rust are in the set partly to keep Swift honest: both have a function keyword a
Swift-only detector would misread. JavaScript and TypeScript share an `ecmaScript` supporting
list so neither can win on syntax they have in common; untyped modern ECMAScript ends up
`javascript`, the label that stays true either way. HTML is weighted towards document-level
elements so JSX inside a TypeScript component does not outscore the TypeScript around it.

## Shared with dictation

`CodeLanguage` lives in `UttrflowCore`, so the clipboard and the dictation modules ask one
detector with one scoring table. Two more entry points serve callers that hold something other
than a whole clip:

- `detect(fragment:)` reads the last `fragmentLength` characters before a caret, drops the line
  the window cut through, and applies the same bar and margin. A fragment is shorter than most
  clips, so it answers `nil` more often, which is the intended direction.
- `from(fileName:)` maps a file name's extension through one table. An extension outside the
  thirteen languages answers `nil`; it never guesses a near neighbour.
