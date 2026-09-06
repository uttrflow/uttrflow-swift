# Re-indenting a code clip

`CodeReindent.reindented(_:)` makes a clip's indentation consistent, or answers `nil` and the
panel simply does not offer the action. A wrong answer is a corrupted paste that may reach
production, so every threshold is set on that asymmetry.

## The two claims

Whitespace-only normalisation cannot change what code means only if:

1. Nothing but leading whitespace is touched. Every line is rebuilt as `newIndent + oldBody`,
   so a dropped line or an edited literal is not expressible. Line count, trailing whitespace,
   the final newline, `\r` endings and blank lines survive for the same reason.
2. The leading whitespace *is* indentation. Inside a Swift `"""` or Python `'''` block it is
   printed text; a tab at the front of a makefile recipe is grammar. Most of the type is spent
   deciding whether it understands the clip.

## Refusals

- One line, or an empty clip.
- Any `"""` or `'''` (Swift, Python, Scala, Kotlin, Groovy multi-line strings).
- Any backtick: a JavaScript template literal may span lines, and telling it from a markdown
  fence or a shell substitution means pairing backticks across the whole clip.
- A heredoc opener (`<<TAG`, no space, which keeps `cout << x` and `list << item` out).
- A line with an odd number of unescaped double quotes: a string continuing onto the next
  line. `\"` is discounted, or `print("a \" b")` would refuse every clip containing one.
- A makefile: a tab-indented line directly under a rule at column zero. This also refuses
  `def f():` with a tab-indented body, which is welcome; tab-and-space Python is exactly the
  clip where a wrong level moves a statement into a different block.
- A line mixing tabs and spaces in its indent.
- No space-indented line to measure (an all-tab clip is already consistent).
- A smallest indent of 1 (no language's level, and it would wave every width through) or more
  than 8 (past the widest indent anybody sets).
- Widths that are not all multiples of the smallest: 2, 4 and 6 agree on 2; 4 and 6 agree on
  nothing.
- A jump of more than one level between consecutive non-blank lines. Code enters one block at
  a time; a bigger jump means tabs stood for four columns while spaces counted in twos.

The first non-blank line seeds the level comparison rather than column zero, because clips are
usually cut from the middle of a file. Tabs win the target only outright; a tie goes to spaces,
the smaller edit, since every space-indented line then comes out byte-identical.
