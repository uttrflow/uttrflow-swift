# Can the app see a person fixing a dictated word, without a watcher?

The first question of the auto-learn programme: three ways to notice that the person rewrote a word
in text the app inserted ("git push" heard as "gate push", retyped as "git"). Nothing is stored or
sent by any channel here. The measurements are one run per app on one Mac; the row is in
[probe-log.md](probe-log.md) (#4466).

## How it was measured

A throwaway program (not committed) activated the app, put a field in focus and then:

1. pasted `run git gate push now` (the insertion);
2. read the field's value and selection, the same two reads the dictation context makes;
3. moved the caret back nine characters, deleted `gate` and typed `git`, as a person would;
4. rewrote the whole value through the Accessibility value write, as a script or autocorrect might;
5. re-read the same retained element at 20 s and 120 s after the insertion, with the app in front at
   20 s and Finder in front at 120 s;
6. throughout, held an Accessibility observer for value-changed and selected-text-changed on that
   element, and read the target's CPU time over 20 s and over 10 idle seconds.

The Mac was not quiet: the one-minute load average was 40 to 130 during the runs, so every
microsecond and CPU figure is an upper bound.

## Channel 1: the caret-context read, no watcher

The read keeps the line before the caret up to `FocusedFieldSnapshot.lineReadLimit` (4353
characters: 4096 for the prompt search plus 256 for a typed line plus one), and stops at the
line start. Measured: in every app that answered, right after the insertion the text before the
caret held the whole insertion, 21 characters back. After the person's fix the caret sat mid-line
and the old words were gone from the value, so **the insertion is recoverable only if the app
kept its own copy**; the field then holds the corrected text, and the difference between the two
is the learnable pair. The read reaches the insertion while the caret stays on the same line and
within `lineReadLimit`; a new line (Return) puts the insertion before the line start and out of reach.
It is free, but it fires only at the next dictation, which may be minutes or hours later.

## Channel 2: one bounded read at 20 s and 120 s

The value, the selection and the edit were all still readable on the retained element at both
times in TextEdit, Notes, Terminal and the Safari address bar, in 80 to 3400 µs. Safari took
the longest at 120 s (3.3 ms) and Notes 1.7 ms. In Chrome the retained element
answered at 20 s but not at 120 s once another app was in front: the read returned no value, and
re-reading after returning to Chrome also failed. A read at a delay therefore has to resolve the field
again, which works only while that field is still the focused one.

## Channel 3: value-changed notifications

Registration succeeded in all five apps. A typed fix produced one value-changed per keystroke
(7 in TextEdit and Chrome, 8 in Notes, 14 in Safari, 16 in Terminal) plus one selection-changed per
caret move. Idle cost: TextEdit 0.001 s of CPU in 10 s, Terminal 0.002 s, Safari 0.008 s, Notes
0.19 s and Chrome 0.32 s (both under heavy load, and neither is measured without the observer, so the
share due to it is not separated). The observer's own process used under 0.01 s.

## Telling an edit from autocorrect or a script (#4336)

None of the channels says who wrote. A person's fix is a burst of one-character changes; an
Accessibility value write is one change (TextEdit, Chrome, Notes), though Safari fired
three. An autocorrect or a paste-over is also one change, so **a single big change cannot be told
from a script or autocorrect, and a burst can only be told by timing**. The Terminal accepted
the value write (no error) but fired no notification, so its line is changed only by keystrokes.
In Chrome the caret went to 0 after a value write, in the others to the end.

## Table

| App | Field | Insertion recoverable from the value | Edit visible | Channel 1 | Channel 2 (20 s / 120 s) | Channel 3 | Edit vs script |
|---|---|---|---|---|---|---|---|
| TextEdit | text area | yes | yes | yes | yes / yes | yes, 7 changes | burst vs 1 change |
| Notes | text area | yes (value unreadable before first text) | yes | yes | yes / yes | yes, 8 changes | burst vs 1 change |
| Chrome | web textarea | yes | yes | yes | yes / no | yes, 7 changes | burst vs 1 change; caret reset |
| Safari | address bar only | yes | yes | yes | yes / yes | yes, 14 changes | burst vs 3 changes |
| Terminal | whole screen as one area | yes, inside the screen text | yes | yes, with the prompt | yes / yes | yes, 16 changes | write ignored |

A 5000-character line came back whole in 5020 characters from TextEdit and Notes and 5021 from the
Safari address bar; Terminal answers with its screen, not a line.

## Recommendation

Use **channel 1**, the read the app already makes before each dictation, compared with the
text it inserted last: it needs no watcher, no timer and no second permission, and it carries
the same refusals as insertion. Add **channel 2** only as a read of the field that is still
focused. Do not build a **channel 3** watcher yet: it costs a registration per field and cannot
tell a person from a script.

Learning stays **off** in: a terminal (the value is a whole screen and the shell line is edited by
the shell, not the field); any field that is secure or whose value is empty while text is shown (a
rich editor's hidden input, [web-field-probe.md](web-field-probe.md)); an address bar; and Chrome after
focus leaves the field. Learn only a corrected word, never a rewritten line.

## Not probed

A secure field (no password was typed into a real one). A code editor: Zed and Cursor are IDEs and
could not be launched or driven here, and Cursor publishes no focused element
([compatibility.md](compatibility.md)). A Safari web textarea: the page was not reached, so only the
address bar was read. Autocorrect itself (only a stand-in value write), a field rewritten by a
page script, long delays beyond 120 s, an idle machine, and CPU per channel separately.
