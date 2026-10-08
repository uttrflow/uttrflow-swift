# Released store fixtures

One folder per released tag, holding each local store's file as that release writes it, so
`ReleasedStoreFixtureTests` opens last release's files with this build's code.

- Each file holds the bytes the release wrote, and the test places them unchanged on an
  installation with no store key yet, as an upgrade finds them; a store that seals its file
  must have sealed it once it has been opened.
- Content is invented. `make pii-audit` applies to these files.
- A folder is never edited after its release: a later shape change must still open it.
- An entry of `LocalStoreEntry` without a fixture is listed in the test's `uncovered` set;
  a new entry fails the test until it is placed in one or the other.
