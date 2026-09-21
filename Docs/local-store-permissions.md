# Who may read the local store

Everything Uttrflow keeps about a person is under `~/Library/Application Support/Uttrflow/`:
the clipboard and the pictures in it, the dictation history, the personal dictionary, the
snippets, the suggestion corpus and the waiting recordings. None of it is ever sent anywhere,
so the file modes are the whole of its protection.

`Sources/UttrflowCore/Support/PrivateFile.swift` is the one place that writes it: folders at
`0700`, files at `0600`, owner only.

## Why a helper rather than a rule

Foundation writes under the process umask. On a Mac that is `022`, so `data.write(to:)` lands
at `0644` and `createDirectory` at `0755` — world-readable, both of them, with nothing at the
call site to suggest it. Every store in this app reached for those two calls, and every one of
them got the same answer.

What stood between that and a reader was one accident of the platform: `~/Library` and
`~/Library/Application Support` are `0700` by default, so the loose modes inside never
mattered. They stop mattering the moment the files are copied somewhere that keeps their own
modes — a migration, a `tar` or `rsync` of the folder, an external disk, a backup restored
elsewhere — or on a Mac where somebody has loosened the folders above.

## What the helper does

- `makeDirectory(at:)` makes the folder and its parents at `0700`, then sets the mode again.
  `createDirectory` applies its attributes only to folders it creates, so a folder that was
  already there keeps whatever mode it had; setting it afterwards is what tightens an install
  that predates this.
- `write(_:to:)` makes the folder, writes atomically, then sets `0600` on the result. The mode
  goes on afterwards because an atomic write does not rewrite the file — it writes a temporary
  one beside it and renames, so the mode set before the write belongs to a file that is already
  gone.
- `tighten(at:)` is for bytes this app does not write itself. The suggestion corpus is
  SQLite's file, and SQLite creates `-wal` and `-shm` in the mode it finds on the database, so
  tightening the database once is what makes the other two private as well.

`write` reads the file's owner bits *before* the write and puts them back on the replacement,
because an atomic write does not rewrite the file and the replacement's mode is the umask's rather
than the old file's. Reading them afterwards would quietly restore write permission to a file
somebody had made read-only.

All three tighten by taking group and other away and leaving the owner's own bits as they are.
That is the difference between "nobody else may read this" and "this is 0700", and only the
first is the app's business: somebody who made the folder read-only meant it, and a helper that
set `0700` unconditionally would hand write permission back on the next save without saying so.

## The window this leaves

Between the rename and the mode being set, a freshly created file is whatever the umask made
it. The folder around it is already `0700` by then, so the window is not reachable by another
user on the Mac; it is a window in the file's own mode, not in its reachability. Closing it
would mean giving up the atomic replace, and a file the user can lose is worse than a file
that is briefly `0644` inside a folder nobody else may enter.

## Keeping it true

`Scripts/store_permissions_audit.py` runs in `make verify` and fails on any `createDirectory`,
`createFile`, `write(to:)` or `open(..., O_CREAT, ...)` in `Sources/` that does not go through
`PrivateFile`. Each path still allowed to write for itself states its reason in that file and
prints it on every run, and names the calls it is excused: the evaluation harness, the developer
tools and the model and tokenizer downloads carry no user data and are excused everything, while
the instance lock and the recording writer are excused only `open`, which they need for the
descriptor and already give `0600`. A file excused one call is still held to the rest.

The audit exists because the fix is mechanical and the coverage is not. A store added next year
will reach for `data.write(to:)` exactly as every store before it did, and nothing about that
line looks wrong.
