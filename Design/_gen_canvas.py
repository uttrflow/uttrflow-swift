"""Canvas layout: one labelled row per part of the product, one page.

Rows are stacked automatically from their own artboard heights, so adding a
screen never means hand-editing a y coordinate — which is how the old fixed
coordinates would have drifted the moment the sidebar rows landed.
"""
import json

MAIN = (980, 700)      # every screen inside the app shell
SIGNIN = (660, 760)
ONB = (700, 550)       # every first-run page

ROWS = [
    ("identity",
     "Identity\nThe mark, the app icon and the purple ramp. Every colour below is used somewhere in the rows underneath. Beside it, four wave marks — the drawn glyph cannot hold the menu bar, and each of these is an answer to that.",
     [("Identity.dc.html", 900, 780, None)]),

    ("sign-in",
     "Before anything\nSigning in is required — there is no way past this screen and no \"continue without an account\". In exchange the screen states plainly that this one step needs the network, and that nothing after it does. Light, dark, and the same screen with no connection. It is step 1 of 7 and now carries the dot to say so. The Google and GitHub marks are stand-ins: both providers require their own supplied file, which the app has yet to be given.",
     [("Sign-In.dc.html", *SIGNIN, None), ("Sign-In-Dark.dc.html", *SIGNIN, None),
      ("Sign-In-Offline.dc.html", *SIGNIN, None),
      ("Sign-In-Offline-Dark.dc.html", *SIGNIN, None)]),

    ("onboarding",
     "First launch\nSeven screens, one decision each, and the dots say so on every one of them — including sign-in, which is step 1 and used to draw none. Only the microphone is truly required; everything else can be skipped and repaired later. The download and the microphone check are drawn in every state they can be in, because both can stop halfway. The check is a check: it measures a noise floor, one accuracy reading, and which languages were spoken, and nothing on it may suggest it is learning anybody's voice.",
     # Light and dark side by side, the way the sign-in row above pairs them,
     # so the two appearances of one page can be read against each other rather
     # than eight thousand pixels apart.
     [pair for stem, title in [
         ("Onboarding-Welcome", None),
         ("Onboarding-Microphone", None),
         ("Onboarding-Accessibility", None),
         ("Onboarding-Setup", "Speech model — downloading"),
         ("Onboarding-Setup-Failed", "Speech model — stopped"),
         ("Onboarding-Check", "Microphone check — offering"),
         ("Onboarding-Check-Room", "Microphone check — the room"),
         ("Onboarding-Check-Reading", "Microphone check — reading aloud"),
         ("Onboarding-Check-Done", "Microphone check — finished"),
         ("Onboarding-Check-Failed", "Microphone check — failed"),
         ("Onboarding-Ready", None),
     ] for pair in (
         (f"{stem}.dc.html", *ONB, title),
         (f"{stem}-Dark.dc.html", *ONB, title and title + " (dark)"))]),

    ("in-use",
     "Every day\nThe floating button is the whole product for most people. It is the recorder too — it expands in place rather than a second panel appearing somewhere else.",
     [("Dock-States.dc.html", 900, 780, None), ("Dock-Placement.dc.html", 900, 700, None),
      ("MenuBar.dc.html", 700, 620, None)]),

    ("predict",
     "Tab to complete\nThe suggestion surface, in the five shapes it can take. Which one is drawn is not a preference but a capability: the placement ladder in Docs/predict-probe.md reads what a field publishes, and a field that gives up its caret rectangle gets the inline ghost while one that gives up only its text gets the strip along the bottom of its window. The list is deliberately almost empty — a mark, a string and a Tab glyph, with no counts, percentages or confidence bars — because a number beside a completion has to be priced before a keypress that saves a quarter of a second. The last pair is what the system asks for under Increase Contrast: ghost text measures 2.8:1 on light and 3.9:1 on dark, so it is replaced rather than dimmed.",
     [pair for stem, size in [
         ("Predict-Certain", (820, 500)),
         ("Predict-Choice", (820, 580)),
         ("Predict-Minimised", (820, 480)),
         ("Predict-Window-Strip", (820, 560)),
         ("Predict-High-Contrast", (820, 700)),
     ] for pair in (
         (f"{stem}.dc.html", *size, None),
         (f"{stem}-Dark.dc.html", *size, None))]),

    ("dictation",
     "The app window: Dictation\nThe sidebar turns a utility into an application. Product mark at the top, a flat list of destinations, the active one in accent, and — where a competitor puts a promo banner — your own most recent dictation. Dictation is the home surface: today's list newest first, hover actions on the row, and a rail of the three things the app can actually measure. Empty is a returning user who has not spoken today, so it shows yesterday rather than nothing.",
     [("Main-Dictation.dc.html", *MAIN, None), ("Main-Dictation-Dark.dc.html", *MAIN, None),
      ("Main-Dictation-Empty.dc.html", *MAIN, None),
      ("Main-Dictation-Empty-Dark.dc.html", *MAIN, None)]),

    ("dictionary",
     "Dictionary\nThe words you say that a general model has never heard. Where each came from, how often it earned its place, and how often you undid it. Kestrel has retired itself after seven undos out of fifteen — dimmed, labelled, and restorable. Empty means Uttrflow has not changed a single word of yours yet.",
     [("Main-Dictionary.dc.html", *MAIN, None), ("Main-Dictionary-Dark.dc.html", *MAIN, None),
      ("Main-Dictionary-Empty.dc.html", *MAIN, None),
      ("Main-Dictionary-Empty-Dark.dc.html", *MAIN, None)]),

    ("corrections",
     "Corrections\nThe screen no competitor has. Everything Uttrflow changed: what it heard, what it wrote, why, which dictation, and an undo. A product that quietly rewrites your words owes you this page. Empty here is the good outcome, and says so.",
     [("Main-Corrections.dc.html", *MAIN, None), ("Main-Corrections-Dark.dc.html", *MAIN, None),
      ("Main-Corrections-Empty.dc.html", *MAIN, None),
      ("Main-Corrections-Empty-Dark.dc.html", *MAIN, None)]),

    ("insights",
     "Insights\nOnly what the app already measures: words per day, speaking speed, accuracy against the user's own baseline, language mix, and which apps the words went into. No \"time saved\" tile — it would need a guess at how fast you type, and the artboard says so out loud. Empty waits for seven days rather than charting two.",
     [("Main-Insights.dc.html", *MAIN, None), ("Main-Insights-Dark.dc.html", *MAIN, None),
      ("Main-Insights-Empty.dc.html", *MAIN, None),
      ("Main-Insights-Empty-Dark.dc.html", *MAIN, None)]),

    ("snippets",
     "Snippets\nSay a trigger phrase, get a block of text. List, add and edit in one place — the last row is open in its editor. The empty state teaches the idea with one worked example instead of an illustration.",
     [("Main-Snippets.dc.html", *MAIN, None), ("Main-Snippets-Dark.dc.html", *MAIN, None),
      ("Main-Snippets-Empty.dc.html", *MAIN, None),
      ("Main-Snippets-Empty-Dark.dc.html", *MAIN, None)]),

    ("style-account",
     "Style and Account\nSettings idiom, inside the app window. Style is how much tidying and which languages, with the same sentence shown at both levels so the choice is not abstract. Account is an identity and nothing else — signing out leaves every file where it is.",
     [("Main-Style.dc.html", *MAIN, None), ("Main-Style-Dark.dc.html", *MAIN, None),
      ("Main-Account.dc.html", *MAIN, None), ("Main-Account-Dark.dc.html", *MAIN, None)]),

    ("main-window",
     "History and Diagnostics\nUnchanged in substance, redrawn inside the shell. Today lives on Dictation now, so History starts at yesterday. Diagnostics is still where the PRD's latency and failure numbers surface.",
     [("Main-History.dc.html", *MAIN, None), ("Main-History-Dark.dc.html", *MAIN, None),
      ("Main-Diagnostics.dc.html", *MAIN, None),
      ("Main-Diagnostics-Dark.dc.html", *MAIN, None)]),

    ("settings",
     "Settings\nIts own window, reached from the sidebar. Every choice is worded as an outcome — nothing here asks the user to understand how Uttrflow works.",
     [("Settings-General.dc.html", 800, 660, None), ("Settings-Languages.dc.html", 800, 660, None),
      ("Settings-Dictation.dc.html", 800, 660, None), ("Settings-Privacy.dc.html", 800, 660, None)]),

    ("errors",
     "When things go wrong\nEach failure states one problem and offers one action. The transcript is never lost, whatever fails.",
     [("Errors.dc.html", 900, 700, None)]),
]

GAP = 40
ROW_GAP = 110
artboards, annotations = [], []
y = -860
for note_id, text, row in ROWS:
    x = 0
    for name, w, h, title in row:
        entry = {"file": name, "x": x, "y": y, "w": w, "h": h}
        if title:
            entry["title"] = title
        artboards.append(entry)
        x += w + GAP
    annotations.append({"id": note_id, "x": -360, "y": y, "w": 300, "text": text})
    y += max(h for _, _, h, _ in row) + ROW_GAP

with open("canvas.json", "w") as f:
    json.dump({"artboards": artboards, "annotations": annotations,
               "launch": {"view": "canvas"}}, f, indent=2)
print(f"{len(artboards)} artboards, {len(annotations)} notes")
