# Clipboard memory budget

`ClipboardBudget.standard` is every number that decides how much of this Mac's memory the
clipboard may use. It is not a user setting: nobody has an opinion about a thumbnail cache in
megabytes, and a preference nobody can answer ships set wrong.

## Pools

| Pool | Bytes | Items | Window |
| --- | --- | --- | --- |
| `copied` | 8 MB | 500 | the user's retention setting |
| `dictation` | 4 MB | 500 | the user's retention setting |
| `images` | 32 MB of decoded thumbnails | 500 | 7 days |
| `kept` | no bound | no bound | never |

44 MB claimed against a 64 MB ceiling, which leaves room to raise one tier for a build without
touching the others; a test checks the tiers against the ceiling.

**Measured, not planned:** a live clipboard of fifty-five clips weighs ten kilobytes of text;
five hundred is under a megabyte. The quotas are generous by a factor of ten against real use
and still a fraction of what the app costs to have open. A 68-point thumbnail is about 18 KB,
so 32 MB is roughly eighteen hundred of them.

Bytes and items bound different failures: bytes stop the pool being large; the count stops
the file being long, and the file is rewritten whole on every copy, so a hundred thousand tiny
clips would make every ⌘C a slow write.

## The largest clip

`largestClip` is 2 MB, about a million characters, and it is the one number that stops
unbounded growth: every eviction rule assumes many small things, and one copied log file is one
thing. Before the cap a two-hundred-megabyte copy went into the list and stayed, making every
later ⌘C a two-hundred-megabyte write. Nothing that long is read in a panel of forty-point rows,
and the text is still on the system clipboard. This is the only case where Uttrflow declines to
remember something on purpose. It applies on the way in; a clip becomes kept after it is held,
so it was under the cap when it arrived. The store checks the same combined plain-and-rich-text
weight after edits, too; an edit that crosses the cap is refused without changing the saved copy.

`PasteboardWatcher` asks the cap before it classifies, because `ClipKindDetector` reads the whole
string — about 2.9 s per megabyte — and leaving the question to the store spent all of that on a
clip it was going to refuse, with the poll loop stopped meanwhile. Both count the same bytes: the
plain text plus the formatted flavour, as `ClipboardStore.weight(of:)` does. The store still asks
too, because a clip also reaches it from dictation and from the panel.

## A copied picture

A picture is read as PNG without an uncompressed copy in between. When the clipboard carries
PNG already, which a screenshot copied with the keyboard does, those bytes are kept as they are
and the size is read from the header, so nothing is decoded. Any other flavour ImageIO reads
(TIFF, HEIC, JPEG) is decoded once and encoded once as PNG. `NSImage` is left for the flavours
ImageIO cannot read. Before this, every picture went through `tiffRepresentation`. Measured
headlessly on a 5120 × 2880 PNG of 0.3 MB: the TIFF in between was 56 MB and peak memory rose by
about 233 MB for each picture copied, whether or not the panel was ever opened. Reading the same
bytes as they are and the size from the header raises it by about 3 MB.

## The largest picture

A picture is judged by its header before a pixel of it is decoded. ImageIO reads the width and
height from the file's properties, and two numbers in `ClipboardBudget` decide what happens next:

| Bound | Standard | What it does |
| --- | --- | --- |
| `largestPicture` | 150 megapixels | A header claiming more is refused: nothing is decoded and no clip is made. |
| `pictureEdge` | 4096 pixels | A picture that has to be converted is decoded no longer than this on its longest side. |

A refusal is like `largestClip`'s: the picture is still on the system clipboard, and the log says
`a copied picture of W×H is over the bound; it is not kept`. Zero turns either bound off.

A picture over the edge is downsampled while it is decoded, with
`CGImageSourceCreateThumbnailAtIndex`, so its full-size bitmap never exists. PNG bytes within
`largestPicture` are still kept as they are, whatever their size, because keeping them decodes
nothing; the panel's thumbnail is drawn from them at 68 pixels by the same ImageIO call.

The flavours are asked for compressed first — PNG, HEIC, JPEG — and TIFF last. Asking the
pasteboard for TIFF when the writer offered only JPEG or HEIC makes macOS translate the picture
into an uncompressed TIFF inside Uttrflow's own process, before any of this code sees a byte.

**Measured**, headlessly on this Mac, for a 12000 × 12000 picture, peak memory above the bytes
read from the clipboard:

| Copied as | Before | After |
| --- | --- | --- |
| JPEG, 4.3 MB, through a pasteboard | 1,464 MB, 28.9 s | 359 MB, 2.5 s, stored 4096 × 4096 |
| HEIC, 0.3 MB, through a pasteboard | 1,782 MB, 10.2 s | 148 MB, 1.0 s, stored 4096 × 4096 |
| TIFF, 576 MB, its bytes | 584 MB, 5.4 s | 283 MB, 3.5 s, stored 4096 × 4096 |
| PNG, 2.6 MB | 1 MB, kept as it is | 1 MB, kept as it is |

The ceiling sits just above the picture measured here, so the largest picture that is decoded at
all is one of this size. The edge keeps a 4032 × 3024 photograph and a 4K screen at full size. A
smaller edge costs less — about 90 MB at 2048 for the same pictures — and keeps less of the
picture that is pasted back.

The work runs on the watcher's read queue, never the main thread. `readLimit` stops the watcher
waiting for it; these bounds are what stop the work itself.

## Kept

A clip the user named, filed or pinned has no quota, no window and no replacement policy. Kept is
asked first when classifying, so a pinned screenshot is not a picture and the seven-day window
cannot delete it.

Pinned pictures are the one exception: their bytes still count toward the disk budget, even
though eviction cannot touch them. The 1 GB ceiling is therefore a bound on the total picture
bytes on disk, pinned or not; pinning enough large screenshots to overflow it is what the user
asked for, and `withinDisk` will keep evicting unpinned pictures to make room for the next
copy. A pinned picture set that has already overflowed the cap stays in place until the user
unpins; eviction is still exempt, by the kept pool's rule.

