# Which field of an application the words go into

The destination is chosen per application, so every field of a code editor, SQL client, chat
app, mail app or terminal gets that family's rules unless `DestinationFormatter.fieldKind(of:)`
tells it apart. This page holds the fields each family has besides its main surface, and how well
the signals the field read carries (role, subrole and label) separate them today.

## The fixtures

Twenty-one snapshots `surface-*.json` in `Tests/Fixtures/AccessibilitySnapshots/`, in the
`AccessibilitySnapshot` schema: the main surface of each family and at least three other fields.
`SurfaceSeparationTests` reads each through `FocusedFieldRead.names` and the line mode the
focused-window read banks, then asks `DestinationFormatter.fieldKind(of:)` with the family's
destination:

```bash
swift test --filter SurfaceSeparationTests
```

**These are built by hand, not recorded**, and every shape is *assumed*: an AppKit text view is
an `AXTextArea`, a text field an `AXTextField`, and a search field an `AXTextField` with the
subrole `AXSearchField`. The text is invented. A live recording replaces a fixture file without
changing the test's code; only its measured kind moves.

## Recording a fixture

```bash
swift run uttrflow-dev probe snapshot --family "native text area" --output Tests/Fixtures/AccessibilitySnapshots/native-text-area.json
make snapshot-fixture-audit
```

The recorder asks the focused field every attribute the focused-field read may ask, each timed,
plus one ranged read and the window's subtree to depth 8 and 160 elements. It never writes what
was on screen: every text is replaced by invented text with the same UTF-16 length, line breaks,
Unicode block (so the script holds) and character class, without `@ . : /`. Roles and subroles
are kept; a window title and a document keep only their extension. A value the schema cannot
hold, such as a range or a point, is left out. `make snapshot-fixture-audit` fails on an email
address, a postal address, nine or more digits, or a host off the reserved domains in any fixture.

| Family | Field | Role | Subrole | Label | Kind today |
|---|---|---|---|---|---|
| code editor | source text (main) | `AXTextArea` | | source editor | primary |
| code editor | find bar | `AXTextField` | `AXSearchField` | Find | one-line |
| code editor | find box drawn by a web engine | `AXTextArea` | | Find | **primary** |
| code editor | rename box | `AXTextField` | | Rename symbol | one-line |
| code editor | command input | `AXTextField` | | Type a command | one-line |
| SQL client | query editor (main) | `AXTextArea` | | query editor | primary |
| SQL client | connection dialog host | `AXTextField` | | Host | one-line |
| SQL client | result grid cell | `AXTextField` | | | one-line |
| SQL client | filter row | `AXTextField` | | Filter rows | one-line |
| chat | message composer (main) | `AXTextArea` | | Message #garden-club | primary |
| chat | search box | `AXTextField` | `AXSearchField` | Search | one-line |
| chat | thread title | `AXTextField` | | Thread name | one-line |
| chat | channel topic | `AXTextArea` | | Topic | **primary** |
| mail | message body (main) | `AXTextArea` | | | primary |
| mail | recipient | `AXTextField` | | To | one-line |
| mail | subject | `AXTextField` | | Subject | one-line |
| mail | search box | `AXTextField` | `AXSearchField` | Search | one-line |
| terminal | shell (main) | `AXTextArea` | | shell | primary |
| terminal | tab title | `AXTextField` | | Tab Title | one-line |
| terminal | find bar | `AXTextField` | `AXSearchField` | Find | one-line |
| terminal | settings search | `AXTextField` | `AXSearchField` | Search | one-line |

## What the probe found

| Family | Other fields resolved as not the main surface | Main surfaces taken for another field |
|---|---|---|
| code editor | 3 of 4 | 0 of 1 |
| SQL client | 3 of 3 | 0 of 1 |
| chat | 2 of 3 | 0 of 1 |
| mail | 3 of 3 | 0 of 1 |
| terminal | 3 of 3 | 0 of 1 |
| all | 14 of 16 (88%) | 0 of 5 |

- **Role** separates every one-line field from the main surface, and never takes a main surface
  for another field. It is the only signal the decision reads for these fixtures.
- **Label** is the only signal that names the two multi-line fields the role leaves on the main
  surface (the web-engine find box, the channel topic). The decision reads a label only when the
  role and line mode say nothing, so neither is resolved. Code editor and chat are **unresolved**
  by role and subrole alone.
- **Subrole** marks five search fields, but the decision reads only the role `AXSearchField`, so
  each is resolved as a one-line field and gets one-line rules, not search rules.
- A mail recipient or subject field with the role `AXTextField` is resolved as a one-line field,
  not as a recipient or subject: its label is not read once the role is known.

## Not measured here

Live recordings from real applications, and which field is the largest multi-line text area of
its window: the snapshots carry no frames.
