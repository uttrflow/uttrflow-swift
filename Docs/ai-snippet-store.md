# The snippet store

`SnippetStore` in `Sources/UttrflowAI/SnippetStore.swift` keeps the user's snippets on this
Mac between launches, at `snippets.v1.json` under Application Support.

## Its own file, beside the history and the dictionary rather than inside either

These are neither the user's words nor a spelling the app learned: they are text the user
wrote once and expects to still be there in a year. Nothing ages them out, and nothing else
may clear them by accident. The version in the name leaves room for a shape too different to
read field by field to be introduced beside this one rather than on top of it.

## An actor, and no cache

An actor for the reason `Docs/history-store-file.md` gives at length — the readers are
windows and the writer is a dictation that has already finished, so waiting should be a
suspension rather than a blocked main thread.

Nothing is cached. `PersonalDictionaryStore` caches because it is read before *and* after
every dictation and rebuilds an index each time; this is read once per dictation and decodes
a handful of records, so the certainty that the file is the only truth is worth more than the
read it would save.

## Creation order, always

The list on screen is edited in place: a row that jumps somewhere else the moment you save it
is a row you then have to hunt for. So `snippets()` answers in creation order, an edit
replaces in place rather than removing and appending, and sorting is the interface's job —
which it can do without the store's order changing underneath it.

## One trigger, one snippet

Two snippets answering to one trigger is a question with no right answer, and the wrong place
to discover it is halfway through a dictation: the matcher would pick one and be consistent
about it, and the user would have no idea which. `save(_:)` refuses with
`SnippetStoreError.triggerAlreadyUsed`.

## Why there is a second `save`

`save(trigger:expansion:replacing:created:)` exists rather than letting the caller build a
`Snippet` and hand it to `save(_:)`. On an edit, the identity, the creation date and both use
counters have to be carried over from the snippet being replaced; a caller that forgot any of
them would silently make a two-year-old snippet look new and reset what had been counted
about it. That is a decision about what a snippet *is*, so it belongs in the store and not in
whichever window happens to be open.

Two details of that call are deliberate:

- The trigger is trimmed. Surrounding space is not the user's.
- The expansion is **not** trimmed. A snippet ending in a newline is a snippet that ends in a
  newline.
- An identifier that is no longer there is treated as new: the row was deleted underneath the
  editor, and refusing would lose what the user had typed.

## Counting use

`recordUse(of:at:)` takes identifiers rather than a `SnippetExpansion`, so the store stays
ignorant of the matcher; the call site passes `SnippetExpansion.usedSnippetIDs`. A snippet
that fired twice appears twice and is counted twice, which is what the user did. Identifiers
that no longer exist are ignored, and a call that changes nothing does not touch the disk — a
dictation with no expansions in it must not rewrite the file.

## Reading and writing the file

Identical in shape and in reasoning to the history store's, and described there: a file that
cannot be read answers as empty rather than refusing to open the app, writes are atomic, and
an emptied list removes the file rather than writing `[]`.
