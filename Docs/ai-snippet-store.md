# The snippet store

A snippet is a trigger phrase the user says and the text it expands to. `SnippetStore` in
`Sources/UttrflowAI/SnippetStore.swift` keeps the user's snippets on this Mac between launches,
at `snippets.v1.json` under Application Support, written through `EncryptedStore` like the
history and the dictionary (`Docs/local-store-encryption.md`). `SnippetExpander` in
`Sources/UttrflowAI/SnippetExpander.swift` matches triggers in a finished dictation.

## Its own file, beside the history and the dictionary rather than inside either

These are neither the user's words nor a spelling the app learned: they are text the user
wrote once and expects to still be there in a year. Nothing ages them out, and nothing else
may clear them by accident. The version in the name leaves room for a shape too different to
read field by field to be introduced beside this one rather than on top of it.

## An actor, and a cache that checks the file

An actor for the reason `Docs/history-store-file.md` gives at length — the readers are
windows and the writer is a dictation that has already finished, so waiting should be a
suspension rather than a blocked main thread.

The decoded list is held by `CachedStoredList`, which reads the file again only when its stamp
— inode, size and modification time — differs from the one it was read at, so the file stays
the only truth without being decoded on every read. `expander()` builds the matcher from that
list at the moment it is asked, never from a list fetched earlier.

## Creation order, always

The list on screen is edited in place: a row that jumps somewhere else the moment you save it
is a row you then have to hunt for. So `snippets()` answers in creation order, an edit
replaces in place rather than removing and appending, and sorting is the interface's job —
which it can do without the store's order changing underneath it.

## One trigger, one snippet

Two snippets answering to one trigger is a question with no right answer, and the wrong place
to discover it is halfway through a dictation: the matcher would pick one and be consistent
about it, and the user would have no idea which. `save(_:)` refuses with
`SnippetStoreError.triggerAlreadyUsed`. It also refuses a trigger with no words
(`triggerHasNoWords`) and an expansion that is only whitespace (`expansionIsEmpty`).

## Why there is a second `save`

`save(trigger:expansion:replacing:created:)` exists rather than letting the caller build a
`Snippet` and hand it to `save(_:)`. On an edit, the identity, the creation date, the use
count and the last-used date have to be carried over from the snippet being replaced; a caller
that forgot any of them would silently make a two-year-old snippet look new and reset what had
been counted about it. That is a decision about what a snippet *is*, so it belongs in the store
and not in whichever window happens to be open.

Three details of that call are deliberate:

- The trigger is trimmed. Surrounding space is not the user's.
- The expansion is **not** trimmed. A snippet ending in a newline is a snippet that ends in a
  newline.
- An identifier that is no longer there is treated as new: the row was deleted underneath the
  editor, and refusing would lose what the user had typed.

## Where the caret ends

A body may hold `{caret}` once to say where the caret ends after the expansion is written,
so a stock paragraph can leave the caret at the name still to be typed. `SnippetBody` in
`Sources/UttrflowCore/Models/Snippet.swift` is the one place a marker is read: the expander
writes the body without it, `AppliedSnippet.expansion` and so the history never hold it, and
`SnippetExpansion.caret` and `ExpandedTranscript.caret` carry where it was, in UTF-16 units of
the text to insert. Only the first marker of the first marked firing counts; later ones are
dropped. `\{caret}` writes the marker text itself. Export and import carry the stored body
unchanged, markers included.

The caret is moved by `SelectionWriter.placeCaret(in:back:)`, which verifies the recorded
span exactly as an edit of it does (`Sources/UttrflowInput/EditTarget.swift`) and refuses a
field that will not report ranges, so the caret stays at the end of the expansion there. A
body that is only a marker is empty and is refused like one.

## When a snippet does not fire

A snippet does not fire when the transcript also contains its expansion's words anywhere:
someone who says the expansion is quoting it, not triggering it. The veto reads the whole
transcript, not the trigger's position.

## Counting use

`recordUse(of:at:)` takes identifiers rather than a `SnippetExpansion`, so the store stays
ignorant of the matcher; the call site passes `SnippetExpansion.usedSnippetIDs`. A snippet
that fired twice appears twice and is counted twice, which is what the user did. Identifiers
that no longer exist are ignored, and a call that changes nothing does not touch the disk — a
dictation with no expansions in it must not rewrite the file.

## Reading and writing the file

Identical in shape and in reasoning to the history store's, and described there: a file that
cannot be read answers as empty rather than refusing to open the app and is renamed aside, a
write is refused while the store holds an unreadable read so it cannot write over the only copy,
writes are atomic, and an emptied list removes the file rather than writing `[]`.
`deleteEverything()` also removes any copy set aside from an unreadable file.

## Related pages

- `Docs/history-store-file.md` — the file-handling rules this store shares.
- `Docs/personal-data-archive.md` — exporting and importing snippets.
- `Docs/latin-output.md` — an expansion is inserted in Latin letters whatever script it was written in.
