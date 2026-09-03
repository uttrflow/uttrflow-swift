# Accepting a suggestion

What happens between the user pressing a key and the completion appearing in their
document. The deciding is `KeyRouting` in `UttrflowPredict`, which is pure; the tap is
`KeyInterceptor` in `UttrflowInput`, which is not and is excluded from the coverage gate
for it.

## Which key accepts

Tab by default. The right arrow in terminals, because Tab there is the shell's own
completion and taking it would break the thing the user is actually trying to do.
Option-Tab in editors, because Tab there is indentation and the language server's
completion is already bound to it. The user can override any application, and the
override wins over the kind.

`AcceptKeys` recognises terminals and editors from a bundle-identifier prefix.
`AppKind` in `UttrflowAI` recognises overlapping sets for a different purpose — the one
line of prompt text that describes the screen — and the two tables are deliberately not
shared, because `UttrflowPredict` depends on nothing and `UttrflowAI` depends on Core and
the dictionary. If a third caller ever needs the classification, the table moves into
Core and both read it; two is not enough to pay for that.

## Return is the dangerous key

A suggestion on screen does **not** entitle us to Return. Stealing it runs a command in a
terminal and sends a half-written message in a chat box, and both are unrecoverable in a
way that a missed completion is not. So Return passes through untouched until the user has
pressed Down at least once — the moment they are demonstrably navigating our list rather
than finishing their own line. `SuggestionSelection.hasMoved` is that fact and nothing
else.

The same reasoning applies to Up, which is shell history before it is anything of ours: it
is claimed only once the list is being walked. A single suggestion is not a list at all,
so neither arrow nor Return is ever claimed for one — Tab is the only way to take it.

## The escape ladder

| Keystroke | Effect |
|---|---|
| ⎋ | The suggestion goes; the dot stays |
| ⎋⎋ | This field offers nothing more |
| ⌥⎋ | Suggestions stop everywhere until turned back on |

⎋ with nothing drawn is not ours: it closes the application's own dialog, and a tap that
swallows it is a tap the user has to quit the app to escape from.

## Why the tap swallows from a bitmask

The tap's callback runs inside the window server's event path for **every keypress in the
system**, ours or not, and macOS disables a tap that takes too long over one. So the
callback allocates nothing, takes no lock, and asks one question: is the bit for this
keystroke set in one atomic `UInt32`?

`ArmedKeys` is that word — one bit per keystroke the feature can ever claim — and
`KeyRouting.arming` computes it *from `KeyRouting.decision` itself*, over every slot. The
mask and the rules therefore cannot disagree about what is taken, which matters because a
key swallowed with no rule behind it is a keystroke the user silently loses. There is a
test that asserts the agreement directly.

A swallowed keystroke is written into a fixed ring buffer of 64 entries and a dispatch
source is signalled; the decision runs on that source's queue. The ring is what keeps two
quick presses of Down from coalescing into one, which a source's own OR-ed data would do.

The tap gets its own thread with its own run loop. A tap serviced by the main run loop is
a tap that stalls behind whatever the app is drawing, and the system's answer to a stalled
tap is to switch it off.

## Being switched off

macOS disables an event tap that misses its deadline (`.tapDisabledByTimeout`) and when
the user's own input demands it (`.tapDisabledByUserInput`). The callback turns it back on
once. On a second disable it stops re-arming and reports `.disabledTwice` instead: a tap
that has to be revived repeatedly is one that is costing the user keystrokes, and a
feature that quietly fights the system forever is worse than one that says it has stopped.

## The clipboard is not on the insertion route

Dictation's route ends in the clipboard, because §19 says a user must never lose words
they spoke. A completion is the opposite case: the user did not produce this text, they
merely declined to type it, and losing it costs them one keypress.

Meanwhile putting it on the clipboard costs them their actual clipboard **and** files a
phantom entry in their own clip history — from a feature they experience as autocomplete.
So `TextInsertion.completion` is Accessibility first and synthesised keystrokes second,
with nothing beneath, and a completion that lands nowhere is simply not accepted.

Only the tail is inserted: the head is already in the field, the caret is at the end of
it, and no route here can replace text the user did not select. A suggestion that does not
continue what was typed therefore cannot be accepted at all, and `Acceptance.remainder`
returns nothing for it.

## Not settled here

- **Case-insensitive continuation.** `Git com` does not accept `git commit` today. Doing
  it properly means replacing the typed head, which needs a selection the insertion route
  does not have.
- **Whether ⌘Z reverts an accepted completion in one step.** A property of each target
  application; it needs the surface sweep in `Docs/predict-probe.md` to have been run.
