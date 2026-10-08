# Words the app shows

Nothing is translated yet. This page holds the rule that keeps every new string ready to be.

## The rule

A view shows text through `String(localized:comment:)`, never through a fixed literal:

```swift
Text(String(localized: "Clear the search", comment: "Settings search field, clear button"))
```

The comment tells a translator where the words appear and what they do. One line, in English.

`make string-audit` counts, per file under `Sources/`, string literals passed straight to
`Text`, `Button`, `Label`, `.help` and `.accessibilityLabel`. The counts are recorded in
`Scripts/string_baseline.json`; a file whose count rises fails the audit, and the counts only
go down. `python3 Scripts/string_audit.py --report` lists every literal still to move.
`Text(verbatim:)` is not counted: use it for text that is never translated, such as a version
number.

## Plurals

A count goes into the string by interpolation, `String(localized: "\(count) words")`, so the
translation can vary it by number. Never choose between two literals with
`count == 1 ? ... : ...`; that fixes English plural rules into the code.

## What is never localised

Dictation output. The words the user spoke are inserted as they were said, in Latin letters,
whatever language the app's interface is in ([product.md](agents/product.md#dictation-and-clean-up)).
The same holds for clipboard contents and AI suggestions: they are the user's text, not the app's.
