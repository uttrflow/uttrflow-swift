# Released store fixtures

One folder per released tag, holding each local store's file as that release writes it, so
`ReleasedStoreFixtureTests` opens last release's files with this build's code.

- Each file is the JSON payload the release seals; the test seals it with a test key, so the
  envelope itself is covered by `EncryptedStoreTests`, not here.
- Content is invented. `make pii-audit` applies to these files.
- A folder is never edited after its release: a later shape change must still open it.
- An entry of `LocalStoreEntry` without a fixture is listed in the test's `uncovered` set;
  a new entry fails the test until it is placed in one or the other.
