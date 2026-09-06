# Code language detection

`CodeLanguage.detect(_:)` labels a code clip when the clip alone says which language it is. The
label decorates a chip and the preview; a wrong label is a small lie the user discounts on
every scan, so `nil` is the usual answer.

## Order

1. Fewer than three characters: `nil`. Two characters cannot carry two independent signals.
2. A fenced block (```` ``` ````): `nil`.
3. Valid JSON with an object or array at the top: `json`. `{ retries: 3 }` fails on its
   unquoted key and falls through; a quoted-key object copied on its own came out of an API
   response far more often than out of a source file.
4. A shebang names its interpreter outright. `perl`, `awk` and `tclsh` fall through rather
   than being forced into `shell`.
5. A SQL statement: no full stop at the end, and no English articles (`the`, `a`, `your`,
   `please`, `should`…) unless the statement corroborates itself (a trailing semicolon,
   `SELECT *`, a second clause keyword). "Select an item from the list below" satisfies every
   clause-shape test you can write.
6. Scoring over the first 4,000 characters (about eighty lines; a minified bundle repeats
   itself and ninety regular expressions over half a megabyte would stall ⌘C).

## Scoring

Strong signals (near-unique to one language: `\(…)`, `module.exports`, `elsif`, `:=`) score
2; supporting signals (consistent with a language: `nil`, `->`, a trailing semicolon) score 1.
Distinct signals count, not occurrences, so `console.log` forty times is one signal.

- **Bar: 3.** One near-unique marker plus something corroborating, or three corroborating
  ones. What three rules out is the single token: `->` is Rust, Python, PHP and C++; `let` is
  Swift, JavaScript and Rust; `end` is Ruby and Lua; `func` is Swift and Go.
- **Margin: 2.** The winner must lead the runner-up by the weight of a near-unique signal.
  This protects Swift from TypeScript, which share `let`, `import`, a function keyword and `:`
  annotations. A tie names a family, not a language.

Go and Rust are in the set partly to keep Swift honest: both have a function keyword a
Swift-only detector would misread. JavaScript and TypeScript share an `ecmaScript` supporting
list so neither can win on syntax they have in common; untyped modern ECMAScript ends up
`javascript`, the label that stays true either way. HTML is weighted towards document-level
elements so JSX inside a TypeScript component does not outscore the TypeScript around it.
