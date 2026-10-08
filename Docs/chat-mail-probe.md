# What the dictation read gets from a chat composer or a mail body

Chat and mail are where names matter most and where the text before the caret is least like a
document: a composer can publish its draft only in its description, a reply body starts or ends
with quoted lines, and the recipient is a separate element. This page holds the probe plan for
four such fields and what the focused-field read and the surroundings walk make of each.

## The fixtures

Four snapshots in `Tests/Fixtures/AccessibilitySnapshots/`, in the `AccessibilitySnapshot`
schema, each with its `window` subtree so the surroundings walk replays as well as the field read.
`ChatMailProbeTests` reads each through `FocusedFieldRead` and `Surroundings.collect` over
`WindowReplayTree`, which reads text and conversation lists as the system tree does:

```bash
swift test --filter ChatMailProbeTests
```

**These are built by hand, not recorded.** Each carries invented names and text, and its shape
follows a measured row of [compatibility.md](compatibility.md) where one exists, or is marked
*assumed*. A live recording replaces a fixture file without changing the test's code; only its
expected outcome moves.

| Fixture | Shape | Source | Before the caret | Names the walk finds |
|---|---|---|---|---|
| `chat-native-composer.json` | messages and the composer publish an empty value and their text in the description | measured, chat composer row | empty: the draft is only in the description | thread group label, every message |
| `chat-web-engine-composer.json` | a web area with a navigation landmark, a list of conversation links and the thread | assumed | the draft | thread heading and sender; not the other conversations or the landmark |
| `mail-web-body-quoted.json` | recipient and subject fields beside a body with a quote and list markers below the reply; ranged read refused | assumed | the reply alone above the quote; the quote with its `> -` markers below it | recipient address and subject; not the folder list |
| `mail-native-body-quoted.json` | a recipient field holding a token, then a body opening with a quote and bullet markers | assumed | nothing above the quote; the quote with its `> •` markers below it | subject and window title; **not the recipient** |

## What the probe found

- A composer that publishes its draft only in the description gives the dictation read an empty
  text before the caret, while the walk reads the same description as text for every message.
- A recipient field that names itself in its description and holds the address as a child token
  ends the walk at the field: a text element that says something is a leaf, so the token is never
  read and the recipient's name does not reach the surroundings.
- Quote and list markers are kept verbatim in the text before the caret; nothing classifies the
  caret as inside or outside a quote, so no quoted-reply misclassification is observable here.

## Not measured here

Live recordings from real chat and mail applications. A recording must never send a message:
it is taken from a draft that is discarded afterwards.
