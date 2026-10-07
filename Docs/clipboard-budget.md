# Clipboard memory budget

`ClipboardBudget.standard` in `Sources/UttrflowClipboard/ClipboardBudget.swift` is every number
that decides how much of this Mac's memory and disk the clipboard may use. `ClipboardStore`
enforces it on every save; `PasteboardWatcher` and `ClipboardSource+System.swift` apply the
per-clip and per-picture bounds on the way in. It is not a user setting: nobody has an opinion
about a thumbnail cache in megabytes, and a preference nobody can answer ships set wrong. How the
retention window is chosen is in [`retention-clock.md`](retention-clock.md); where clips are
written is in [`clipboard-store.md`](clipboard-store.md).

## Pools

Each clip is charged to one pool, derived from the clip and never stored on it (`ClipClass`).
Kept is asked first, so a pinned screenshot is kept rather than a picture.

| Pool (`ClipClass`) | What it holds | Bytes | Items | Window |
| --- | --- | --- | --- | --- |
| `kept` | a clip the user named, filed or pinned | no bound, except pictures within `disk` | no bound | never |
| `copied` | text the user copied | 8 MB | 500 | the user's retention setting |
| `dictation` | what Uttrflow made, kept from History or the panel | 4 MB | 500 | the user's retention setting |
| `images` | pictures, whoever put them there | 32 MB of decoded thumbnails | 500 | 7 days |

| Bound | Standard | Field |
| --- | --- | --- |
| All pools together | 64 MB, against 44 MB claimed | `ceiling`, `claimed` |
| The largest single clip | 2 MB | `largestClip` |
| The most pixels a picture's header may claim | 150 megapixels | `largestPicture` |
| The longest edge a converted picture is stored at | 4096 pixels | `pictureEdge` |
| Pictures on disk | 1 GB | `disk` |

The 20 MB between claimed and ceiling leaves room to raise one tier for a build without touching
the others; a test checks the tiers against the ceiling (`ClipboardBudgetTests`). A panel
thumbnail is decoded at 68 pixels (`PanelThumbnails.maxPixel`), 68 × 68 × 4 bytes, about 18 KB,
so 32 MB is roughly eighteen hundred of them.

Bytes and items bound different failures: bytes stop the pool being large; the count stops the
file being long, and the file is rewritten whole on every copy, so a hundred thousand tiny clips
would make every ⌘C a slow write.

Memory and disk quotas evict the least recently used clip by a persisted monotonic sequence
(`lastUsedOrder`), and a repeat copy counts as a use. Wall-clock timestamps still describe when a
clip was used, but a clock adjustment cannot change which clip the quota removes. A clip with no
recorded sequence is placed by its last-use time when the store loads.

## The largest clip

`largestClip` is 2 MB, about a million characters, and it is the one number that stops unbounded
growth: every eviction rule assumes many small things, and one copied log file is one thing.
Without it, one two-hundred-megabyte copy would make every later ⌘C a two-hundred-megabyte write.
Nothing that long is read in a panel of 34-point rows, and the text is still on the system
clipboard. This is the only case where Uttrflow declines to remember something on purpose. It
applies on the way in; a clip becomes kept after it is held, so it was under the cap when it
arrived. The store checks the same combined plain-and-rich-text weight after edits too; an edit
that crosses the cap is refused without changing the saved copy.

`PasteboardWatcher` asks the cap before it classifies, because `ClipKindDetector` reads every
byte of the clip for a credential, and leaving the question to the store would spend that on a
clip it is going to refuse, with the poll loop stopped meanwhile. Plain text already over the
bound is refused before its rich form is copied out. Both count the same bytes: the plain text
plus the formatted flavour, as `ClipboardStore.weight(of:)` does. The store still asks too,
because a clip can also be kept from History or from the panel.

## A copied picture

A picture is read as PNG without an uncompressed copy in between (`PictureFlavour`). When the
clipboard carries PNG already, which a screenshot copied with the keyboard does, those bytes are
kept as they are and the size is read from the header, so nothing is decoded. Any other flavour
ImageIO reads (TIFF, HEIC, JPEG) is decoded once and encoded once as PNG. `NSImage` is left for
the flavours ImageIO cannot read. `tiffRepresentation` is not used, because the uncompressed TIFF
it makes of a 5120 × 2880 screenshot is about 56 MB, for a PNG of well under a megabyte.

The flavours are asked for compressed first (`pictureFlavours`: PNG, HEIC, JPEG, then TIFF).
Asking the pasteboard for TIFF when the writer offered only JPEG or HEIC makes macOS translate the
picture into an uncompressed TIFF inside Uttrflow's own process, before any of this code sees a
byte.

## The largest picture

A picture is judged by its header before a pixel of it is decoded. ImageIO reads the width and
height from the file's properties, and two bounds decide what happens next:

| Bound | Standard | What it does |
| --- | --- | --- |
| `largestPicture` | 150 megapixels | A header claiming more is refused: nothing is decoded and no clip is made. |
| `pictureEdge` | 4096 pixels | A picture that has to be converted is decoded no longer than this on its longest side. |

A refusal is like `largestClip`'s: the picture is still on the system clipboard, and the log says
`a copied picture of W×H is over the bound; it is not kept`. Zero turns either bound off.

A picture over the edge is downsampled while it is decoded, with
`CGImageSourceCreateThumbnailAtIndex`, so its full-size bitmap never exists. PNG bytes within
`largestPicture` are still kept as they are, whatever their size, because keeping them decodes
nothing; the panel checks the header against `largestPicture` before drawing a thumbnail at 68
pixels, and shows its placeholder when the header is too large or unreadable.

The ceiling sits just above a 12000 × 12000 picture (144 megapixels, 576 MB as an uncompressed
bitmap), so the largest picture decoded at all is about that size. The edge keeps a 4032 × 3024
photograph and a 4K screen at full size; a smaller edge costs less memory and keeps less of the
picture that is pasted back. `PictureBoundTests` holds the refusals and the edge.

The work runs on the watcher's dedicated read queue, never the main thread. `readLimit`
(`PasteboardWatcher.defaultReadLimit`, 2 s) stops the watcher waiting for a value. When a read
times out, the watcher releases its wait slot, retries that clipboard generation on the next poll,
and tells the user once that capture is delayed. A timed-out synchronous pasteboard call cannot be
cancelled and may keep its worker blocked after the watcher moves on; `maxOutstandingReads` bounds
wait slots, not those abandoned calls.

## Kept

A clip the user named, filed or pinned has no quota, no window and no replacement policy
(`ClipClass.kept`, `isEvictable` false). Kept is asked first when classifying, so a pinned
screenshot is not a picture and the seven-day window cannot delete it.

Kept pictures are the one exception: their bytes still count toward the disk budget, even
though eviction cannot touch them (`withinDisk`). The 1 GB `disk` bound is therefore a bound on
the total picture bytes on disk, kept or not, and `withinDisk` keeps evicting unkept pictures,
least recently used first, to make room for the next copy.

Since nothing evicts a kept picture, the bound holds for them by refusal instead
(`ClipboardBudget.fitsKeptPictures`, asked on every store write). A write that would take the kept
pictures past `disk`, such as undoing the delete of a kept picture after the space was filled
again, is refused with `ClipboardStoreError.keptPicturesFull`, which tells the user to unpin or
delete a picture; nothing is changed and nothing kept is deleted. A kept set already past the bound,
from a smaller bound or an earlier build, stays in place: every write that does not add to it is
allowed, so it shrinks only when the user unpins or deletes. Zero turns the bound off.
