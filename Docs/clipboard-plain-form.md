# Rich clips as plain text

`RichTextPlainForm` produces the text that goes into a terminal, a code editor, a commit
message or a search field when a formatted clip is pasted there. The rule is that what arrives
must be text a person could have typed: never `<strong>`, and equally never `**bold**`,
because asterisks are noise at a shell prompt.

## Why a hand-written tokenizer

`NSAttributedString(html:)` is main-actor bound, slow enough to be felt on a panel whose
promise is opening instantly, and would pull the AppKit text system into a module that knows
nothing about drawing. The interesting behaviour is also entirely about input that is not
well-formed.

## The guard against eating code

Input with nothing recognisably HTML in it is handed back with only its entities decoded.
`Array<String>` and `if (a < b)` are both what a browser would call markup; here that would
mean a snippet losing a type parameter on the way into an editor. Two signals count as HTML: a
tag naming a real element, or *any* end tag, which code never has (`template <typename T>` has
no `</…>`) and which catches Word's `<o:p></o:p>` and every custom element. Real HTML writes
`&lt;`, so nothing is given up.

`<` begins a tag only when a tag name could follow, so `a < b` in prose is prose. `>` is
never special outside a tag.

## Entities

Decoded in one pass that never re-reads its output, so `&amp;amp;` yields `&amp;` and stops.
`&nbsp;` decodes to an ordinary space: a non-breaking space looks like a space, is not one, and
breaks shell commands and compilers in ways that take minutes to see. Zero-width joiners and
the soft hyphen decode to nothing. C0 controls other than tab and newline decode to nothing.
An unrecognised name is left as written, so `AT&T` survives. The scan for `;` is bounded at
twelve characters so a stray ampersand does not scan a large clip.

## Whitespace

Line breaks are requested, not written, and nothing is emitted until real content arrives:
`<div><p></p></div><br>` requests four breaks and produces none. Headings get a blank line
(separation is plain text's only cue for one); `<pre>` and `<code>` are verbatim; the newline
directly after `<pre>` is dropped scalar by scalar, because CR LF is one `Character` in Swift.

## Lists and links

Checklists are read from Apple Notes (labels the list), several editors (label the items) and
GitHub (a real `<input>` inside). A link is written as `text (url)`; the text alone when it
already is the url (`https://x (https://x)` is what makes people stop trusting a paste) or when
the href goes nowhere without the page (`#section`, a relative path, `javascript:`).
