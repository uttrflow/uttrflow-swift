# Re-indenting and formatting a code clip

The panel offers two ways to tidy a code clip, and offers each only when it is safe.
`CodeReindent.reindented(_:)` in `Sources/UttrflowClipboard/CodeReindent.swift` makes the
indentation consistent, or answers `nil` and the action is not offered. `SystemCodeFormatter`
(`CodeFormatting+System.swift`) runs an installed formatter, and `FormatterGuard` decides whether
its output may be shown. A wrong answer from either is a corrupted paste that may reach
production, so every threshold is set on that asymmetry.

After the user confirms a format or re-indent, the store replaces the clip's plain text and clears
its old HTML, so a later paste matches the confirmed preview. A rich note edited in the panel uses
the separate note-writing action and keeps the HTML the user authored.

## Re-indenting: the two claims

Whitespace-only normalisation cannot change what code means only if:

1. Nothing but leading whitespace is touched. Every line is rebuilt as its new indent followed by
   its old body, so a dropped line or an edited literal is not expressible. Line count, trailing
   whitespace, the final newline, `\r` endings and blank lines survive for the same reason.
2. The leading whitespace *is* indentation. Inside a Swift `"""` or Python `'''` block it is
   printed text; a tab at the front of a makefile recipe is grammar. Most of the code is spent
   deciding whether it understands the clip.

## Refusals

- One line, or an empty clip.
- Any `"""` or `'''` (Swift, Python, Scala, Kotlin, Groovy multi-line strings).
- Any backtick: a JavaScript template literal may span lines, and telling it from a markdown
  fence or a shell substitution means pairing backticks across the whole clip.
- A heredoc opener (`<<TAG`, no space, which keeps `cout << x` and `list << item` out).
- A line with an odd number of unescaped double quotes: a string continuing onto the next line.
  `\"` is discounted, or `print("a \" b")` would refuse every clip containing one.
- A makefile: a tab-indented line under a rule header at column zero, with only blank lines,
  comments or directives between them. This also refuses `def f():` with a tab-indented body,
  which is welcome; tab-and-space Python is exactly the clip where a wrong level moves a
  statement into a different block.
- A line mixing tabs and spaces in its indent.
- No space-indented line to measure (an all-tab clip is already consistent).
- A smallest space indent outside 2…8: 1 is no language's level and would wave every width
  through, and more than 8 is past the widest indent anybody sets.
- Widths that are not all multiples of the smallest: 2, 4 and 6 agree on 2; 4 and 6 agree on
  nothing.
- A jump of more than one level between consecutive non-blank lines. Code enters one block at a
  time; a bigger jump means tabs stood for four columns while spaces counted in twos.

The first non-blank line seeds the level comparison rather than column zero, because clips are
usually cut from the middle of a file. Tabs win the target only outright; a tie goes to spaces,
the smaller edit, since every space-indented line then comes out byte-identical.

## Running a formatter

The panel can run a code clip through an installed formatter, chosen by the clip's language
([`clipboard-code-language.md`](clipboard-code-language.md)), and never does so unasked. The action
is offered only when `isAvailable(for:)` finds the program.

| `KnownFormatter` | Languages |
| --- | --- |
| `swift-format` | Swift |
| `prettier` | JavaScript, TypeScript, JSON, CSS, HTML |
| `black` | Python |
| `rustfmt` | Rust |
| `gofmt` | Go |

- **Found by name in a fixed list of directories, never through the user's `PATH`**, which
  anything can prepend to (`SystemCodeFormatter.directories`: `/opt/homebrew/bin`,
  `/usr/local/bin`, `/usr/bin`, `/opt/homebrew/opt/go/libexec/bin`). The list is an allowlist
  because a poisoned formatter would see every clip it is handed.
- **Run with no shell**, the code on standard input and never as an argument, a
  `KnownFormatter.timeout` of 3 seconds with `terminationGrace` (0.2 s) before it is killed, and
  output capped at `maximumOutputBytes`, four times the largest accepted clip.
- **Guarded before it is offered.** `FormatterGuard.isFaithful(_:to:)` compares the code, literal
  and comment tokens before and after, in order, ignoring only code whitespace and the layout
  punctuation a formatter may add or drop (`,` and `;`), and discards an output that does not
  match. A formatter that dropped a line never reaches the diff the user is shown.

`format(_:as:)` answers `nil` for a fragment that is invalid on its own, which is the common case
for a clip, and on any other refusal.
