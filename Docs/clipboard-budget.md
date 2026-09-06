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
so it was under the cap when it arrived.

## Kept

A clip the user named, filed or pinned has no quota, no window and no replacement policy.
The honest consequence is that the ceiling is a promise about history, not about what somebody
deliberately saved: someone who pins two gigabytes of screenshots has asked for two gigabytes.
Kept is asked first when classifying, so a pinned screenshot is not a picture and the
seven-day window cannot delete it.
