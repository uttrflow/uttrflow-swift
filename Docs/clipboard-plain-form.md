# Rich clips as plain text

`RichTextPlainForm.plainText(fromHTML:)` in `Sources/UttrflowClipboard/RichTextPlainForm.swift`
produces the text that goes into a terminal, a code editor, a commit message or a search field
when a formatted clip is pasted there, and the text the watcher records when a copy carries only
HTML (`PasteboardWatcher`). What arrives must be text a person could have typed: never
`<strong>`, and equally never `**bold**`, because asterisks are noise at a shell prompt.

## Why a hand-written tokenizer

`NSAttributedString(html:)` is not used: it is main-actor bound, slow enough to be felt on a
panel whose promise is opening instantly, and would pull the AppKit text system into a module
that knows nothing about drawing. The interesting behaviour is also entirely about input that is
not well-formed.

## The guard against eating code

Input with nothing recognisably HTML in it is handed back with only its entities decoded.
`Array<String>` and `if (a < b)` are both what a browser would call markup; here that would mean
a snippet losing a type parameter on the way into an editor. Two signals count as HTML: a tag
naming a real element, or *any* end tag, which code never has (`template <typename T>` has no
`</…>`) and which catches word processors' `<o:p></o:p>` and every custom element. Real HTML
writes `&lt;`, so nothing is given up.

`<` begins a tag only when a tag name could follow, so `a < b` in prose is prose. `>` is never
special outside a tag.

## Entities

Decoded in one pass that never re-reads its output, so `&amp;amp;` yields `&amp;` and stops.
`&nbsp;` decodes to an ordinary space: a non-breaking space looks like a space, is not one, and
breaks shell commands and compilers in ways that take minutes to see. Zero-width joiners and the
soft hyphen decode to nothing. C0 controls other than tab and newline decode to nothing. An
unrecognised name is left as written, so `AT&T` survives. The scan for `;` is bounded at twelve
characters so a stray ampersand does not scan a large clip.

## Whitespace

Line breaks are requested, not written, and nothing is emitted until real content arrives:
`<div><p></p></div><br>` requests four breaks and produces none. Headings get a blank line
(separation is plain text's only cue for one); `<pre>` and `<code>` are verbatim, and so is any
element whose inline style sets `white-space` to `pre`, `pre-wrap` or `break-spaces`, which is how
some document editors put runs of spaces on the pasteboard; a child inherits the mode until its
own style sets another (`HTMLWhiteSpaceStack`). The newline directly after `<pre>` is dropped
scalar by scalar, because CR LF is one `Character` in Swift.
`<script>`, `<style>` and `<title>` contribute no text.

Nested list indentation stops growing at `PlainTextRenderer.maximumListIndentDepth`; deeper items
share the last indentation. Converted output is capped at the watcher's configured
`ClipboardBudget.largestClip` in UTF-8 bytes; direct conversion uses `ClipboardBudget.standard`.
Truncated output ends with an ellipsis, or a dot marker sized to a smaller configured byte limit.
The watcher drops the rich HTML flavor so the bounded plain-text clip still fits the single-clip
limit.

The panel shows the character count of a clip's stored plain-text form when it also retains HTML;
the count is the text a plain target would receive, not the size of the HTML source. See
[`panel.md`](panel.md#multiline-clips).

## Checklists

A checklist item is written as `[ ] ` or `[x] ` before its text, so the boxes survive as text a
person could type. A `<ul>` is a checklist when the list is labelled as one (Apple Notes), when
its items are (`data-checked`, `aria-checked`, or a class such as `task-list-item` or
`checklist-item`, as several editors write them), or when an item holds a real `<input>`
checkbox, as Markdown renderers write them. The panel counts these same boxes and never ticks
them; see [`panel.md`](panel.md#checklists-in-notes).

## Links

A link is written as `text (url)`; the text alone when it already is the url
(`https://x (https://x)` is what makes people stop trusting a paste) or when the href goes
nowhere without the page (`#section`, a relative path, `javascript:`). "Already is the url"
ignores the scheme, a trailing slash and the case of the host only: a path, query or fragment
that differs by case is another destination, so `/Report` behind `/report` is printed. A block
boundary or `<br>` inside a link separates its words with one space.
