#!/usr/bin/env python3
"""Prices each recovery route for each error class with a keystroke-level user model; see Docs/repair-cost.md."""

import math
import sys

# Keystroke-level operator times in seconds (Card, Moran and Newell's published values).
KEY = 0.28        # one key press, average typist
POINT = 1.10      # point the pointer at a target
CLICK = 0.10      # press or release a button
HOME = 0.40       # move a hand between keyboard and pointer
THINK = 1.35      # mentally prepare for the next unit of action

# Measured in Docs/performance-dictation.md: wait after key-up, replies all at once and 100 words real time.
SHORT_WAIT = 1.07
LONG_WAIT = 2.75
REDECODE_WAIT = 8.41  # 30 s of speech handed over all at once, the closest row below 100 words

# Both decode paths on the same clips (Docs/repair-cost.md#net-speed): final word error rate, wait after key-up, N clips.
# Faster is early transcription while the key is held; Most accurate decodes the whole recording at key-up.
SETTINGS = {
    "Faster": (0.022, 2.80, 3),
    "Most accurate": (0.022, 7.41, 6),
}
SPEECH_WORDS_PER_SECOND = 2.5
DICTATION_WORDS = 100

# Error class: words wrong in the written text, characters to retype, words to say in a spoken fix.
CLASSES = {
    "wrong word": (1, 6, 1),
    "sound-alike": (1, 5, 1),
    "dropped negator": (0, 4, 1),
    "wrong number": (1, 3, 1),
    "wrong name": (1, 7, 1),
    "lost piece": (0, 45, 8),
}


def say(words):
    """Holding the key, speaking `words`, and waiting for them, as one dictation."""
    return KEY + words / SPEECH_WORDS_PER_SECOND + (SHORT_WAIT if words < 10 else LONG_WAIT)


def redictate_all():
    """Saying the whole dictation again after removing it."""
    return THINK + say(DICTATION_WORDS)


def retype(wrong, chars, _spoken):
    """Pointer to the place, select the wrong word if there is one, type the fix."""
    select = POINT + 2 * CLICK * (2 if wrong else 1)
    return THINK + HOME + select + HOME + chars * KEY + KEY


def app_undo(*_):
    """One Command-Z, assumed one step, then the whole dictation again."""
    return THINK + 2 * KEY + redictate_all()


def undo_last(*_):
    """The app's own shortcut for removing the last dictation, then the whole dictation again."""
    return THINK + 3 * KEY + redictate_all()


def history_undo(*_):
    """Menu bar, History, the row's Undo, then the whole dictation again."""
    return THINK + HOME + 3 * (POINT + 2 * CLICK) + HOME + redictate_all()


def retry(*_):
    """Menu bar, History, the row's Retry, a re-decode of the kept recording; best case, it fixes the word."""
    return THINK + HOME + 3 * (POINT + 2 * CLICK) + HOME + REDECODE_WAIT + THINK


def replace_spoken(wrong, _chars, spoken):
    """Saying "replace X with Y", or "insert Y after X" when nothing was written."""
    return THINK + say(3 + max(wrong, 1) + spoken)


def history_fix(wrong, chars, _spoken):
    """Menu bar, History, the row, select the word in the row, type the fix, confirm."""
    open_row = THINK + HOME + 3 * (POINT + 2 * CLICK)
    return open_row + POINT + 2 * CLICK * (2 if wrong else 1) + HOME + chars * KEY + KEY + SHORT_WAIT


ROUTES = {
    "retype by hand": retype,
    "app undo, redictate (IN.11)": app_undo,
    "undo last, redictate (UX.10)": undo_last,
    "History Undo, redictate": history_undo,
    "Retry (UX.6)": retry,
    "replace X with Y (CM.9)": replace_spoken,
    "History fix (LN.26)": history_fix,
}


def table():
    """Seconds per route and error class."""
    return {route: {name: cost(*shape) for name, shape in CLASSES.items()} for route, cost in ROUTES.items()}


def net_words_per_minute(word_error_rate, wait, repair_seconds, words=DICTATION_WORDS):
    """Net speed of one dictation with its expected errors repaired, and a 95% Poisson band on the error count."""
    errors = word_error_rate * words
    band = 1.96 * math.sqrt(errors)
    speak = words / SPEECH_WORDS_PER_SECOND + wait

    def wpm(count):
        return words / ((speak + max(count, 0) * repair_seconds) / 60)

    return wpm(errors), wpm(errors + band), wpm(errors - band)


def main():
    priced = table()
    names = list(CLASSES)
    print("| route | " + " | ".join(names) + " |")
    print("|---|" + "---|" * len(names))
    for route, row in priced.items():
        print(f"| {route} | " + " | ".join(f"{row[n]:.1f} s" for n in names) + " |")
    for setting, (word_error_rate, wait, clips) in SETTINGS.items():
        for route in ("retype by hand", "replace X with Y (CM.9)"):
            repair = sum(priced[route].values()) / len(priced[route])
            mid, low, high = net_words_per_minute(word_error_rate, wait, repair)
            print(f"{setting} (N={clips}), repaired by {route}: {mid:.1f} net words a minute (95% {low:.1f}-{high:.1f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
