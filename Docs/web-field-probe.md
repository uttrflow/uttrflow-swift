# What the dictation read gets from a web field

A web page's field is published by the browser engine, not by the page, and the two engines this
app meets differ on whether the field is published at all, whether its character range answers,
and whether its selection does ([compatibility.md](compatibility.md), "Browsers"). This page holds
the probe plan for four field types under each engine with the full Accessibility tree on and off,
and what the focused-field read makes of each cell.

## The fixtures

Sixteen snapshots in `Tests/Fixtures/AccessibilitySnapshots/web-*.json`, one per cell of
{textarea, contenteditable, rich editor with a hidden input, address bar} x {Chromium engine,
WebKit} x {full tree on, off}, in the `AccessibilitySnapshot` schema. `WebFieldProbeTests` replays
each through `FocusedFieldRead` with its recorded selection and checks the value kept, the number
of messages sent and whether the page's document answers:

```bash
swift test --filter WebFieldProbeTests
```

**These are built by hand, not recorded.** Each carries invented text and an `example.com`
document, and its shape follows a measured row of [compatibility.md](compatibility.md) where one
exists. Where no row exists the cell takes the most conservative shape, an unpublished element,
and is marked *assumed* below. A live recording replaces a fixture file without changing the
test's code; only its expected outcome moves.

| Field | Engine | Tree | Shape | Source | Value kept | Messages |
|---|---|---|---|---|---|---|
| textarea | Chromium | on, off | value and selection answer, ranged read refused | value and selection measured, single- and multi-line rows; ranged refusal assumed | yes | 8 |
| textarea | WebKit | on, off | value, selection and ranged read answer | assumed | yes | 8 |
| contenteditable | Chromium | on | as the textarea | assumed | yes | 8 |
| contenteditable | Chromium | off | nothing published | assumed, from "only after the switch" | no | 6 |
| contenteditable | WebKit | on, off | as the textarea | assumed | yes | 8 |
| rich editor | Chromium | on | an empty hidden textarea at the caret | measured, rich-editor row | empty | 8 |
| rich editor | Chromium | off | nothing published | assumed | no | 6 |
| rich editor | WebKit | on, off | an empty widened hidden textarea | measured, code-editor row | empty | 8 |
| address bar | Chromium | on, off | value answers, selection refused with no value | measured, address-bar row | no | 6 |
| address bar | WebKit | on, off | no focused element resolved | measured as unknown | no | 6 |

Messages count the five names, the selection, and the character count and value where the read
gets that far.

## Conclusion from the fixtures

- **Relied on:** a textarea under either engine, and a contenteditable with the tree on. The read
  keeps the value in one count and one value message.
- **Not relied on:** any field under the Chromium engine with the tree off other than a textarea,
  and either engine's address bar. The read keeps nothing.
- **A rich editor yields an empty value, not a missing one.** The hidden input answers, so the
  read reports an empty field; the line comes only from the rendered-row read in
  [predict-reliability.md](predict-reliability.md).
- **A refused selection drops a value that answered.** The Chromium address bar publishes its
  value, but the read asks for the character count only with a caret, so it keeps nothing. That is
  the read's own ordering, not the engine's refusal, and is the input the tree-switch decision
  needs before another switch is added.

## Still to measure

Every *assumed* cell, and the engine versions for the [compatibility.md](compatibility.md) rows,
need a recording from the real browsers with `uttrflow-dev probe surface`, written out in this
schema. Until then the table above states what the read does with the documented shapes, not
what the browsers answer.
