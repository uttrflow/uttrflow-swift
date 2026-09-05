"""Tab-to-complete — the five things the suggestion surface can be.

The states here are the placement ladder in `Docs/predict-probe.md` drawn out:
a field that publishes its text, its caret rectangle and its styling gets the
inline ghost; one that publishes text and a caret gets the list under the caret;
one that publishes only its text gets the strip along the bottom of its window;
a secure field gets nothing at all.

Two rules from the operator govern the drawing and neither is negotiable.

The list is only ever the mark, the text and a Tab glyph. No frequency counts, no
percentages, no confidence bars, no legend of keys along the bottom. Ranking is
the order the rows are in, and a number beside a completion is a number the user
has to price before they can press a key that was going to take them a quarter of
a second.

The ghost is the line's own colour at 45%, which is how it stays a ghost in a host
whose colours this app never sees. That is also why state 5 exists: 45% of the ink
measures 2.8:1 on the light host and 3.9:1 on the dark one — computed by the check
at the foot of this file, and both under the 4.5:1 body text owes — so under
Increase Contrast or Reduce Transparency the ghost is replaced by a solid bordered
chip rather than dimmed further.
"""
from _gen_shell import *

# ---- the colours the checks at the bottom are run against ----------------
# Hosts are drawn in the artboard's own appearance, so the ghost is measured
# against the ground it actually sits on rather than a white one.
TERM_BG, TERM_INK = "#FFFFFF", "#1D1D1F"
TERM_BG_D, TERM_INK_D = "#1C1C1E", "#E8E8ED"
GHOST_ALPHA = 0.45

#: The chip drawn instead of the ghost when the system asks for more contrast.
CHIP_BG, CHIP_BORDER, CHIP_INK = "#FFFFFF", "#1D1D1F", "#1D1D1F"
CHIP_BG_D, CHIP_BORDER_D, CHIP_INK_D = "#2C2C2E", "#F5F5F7", "#F5F5F7"

#: The minimised dot carries no text, but it is the only thing drawn, so it is
#: held to the 3:1 a graphical object owes rather than the lighter teals.
DOT, DOT_D = "#128077", "#29C0B4"

MONO = 'ui-monospace, "SF Mono", SFMono-Regular, Menlo, monospace'

PRED_VARS = f"""
    :root {{
      --term-bg: {TERM_BG};
      --term-ink: {TERM_INK};
      --term-chrome: rgba(0,0,0,0.045);
      --chip-bg: {CHIP_BG};
      --chip-border: {CHIP_BORDER};
      --chip-ink: {CHIP_INK};
      --dot: {DOT};
      --panel-bg: #FFFFFF;
      --strip-bg: rgba(246,246,248,0.98);
    }}
    .theme-dark {{
      --term-bg: {TERM_BG_D};
      --term-ink: {TERM_INK_D};
      --term-chrome: rgba(255,255,255,0.06);
      --chip-bg: {CHIP_BG_D};
      --chip-border: {CHIP_BORDER_D};
      --chip-ink: {CHIP_INK_D};
      --dot: {DOT_D};
      --panel-bg: #262628;
      --strip-bg: rgba(44,44,47,0.98);
    }}
"""

PRED_CSS = """
    .caption { width: 600px; margin: 20px auto 0; text-align: center;
               font-size: var(--t-callout); line-height: 1.55; color: rgba(0,0,0,0.50); }
    .theme-dark .caption { color: rgba(255,255,255,0.48); }
    .caption b { font-weight: 600; color: rgba(0,0,0,0.72); }
    .theme-dark .caption b { color: rgba(255,255,255,0.72); }
    .stack-label { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
                   text-transform: uppercase; color: rgba(0,0,0,0.36);
                   margin: 0 0 8px 2px; }
    .theme-dark .stack-label { color: rgba(255,255,255,0.40); }

    /* ---- hosts ---------------------------------------------------------- */
    .hostbar { height: 28px; flex: none; display: flex; align-items: center; gap: 10px;
               padding: 0 12px; background: var(--term-chrome);
               border-bottom: 0.5px solid var(--separator); }
    .hostbar .ttl { font-size: var(--t-footnote); color: var(--label-3); margin: 0 auto;
                    padding-right: 44px; }
    .term { background: var(--term-bg); color: var(--term-ink); }
    .tbody { padding: 12px 14px 16px; font-family: MONOSTACK; font-size: 12px;
             line-height: 1.85; }
    .tline { white-space: nowrap; }
    .tline.past { opacity: 0.42; }
    .prompt { opacity: 0.62; }
    .caret { display: inline-block; width: 1.5px; height: 14px; vertical-align: -3px;
             background: currentColor; }

    /* The completion itself: the line's own colour at 45%, never a colour of
       its own, so it ghosts against a host whose theme this app cannot read. */
    .ghost { opacity: 0.45; }
    .tabmark { display: inline-block; margin-left: 8px; padding: 0 4px;
               border: 0.5px solid currentColor; border-radius: 3px; opacity: 0.38;
               font-size: 9px; line-height: 14px; vertical-align: 1px; }

    /* ---- the list under the caret --------------------------------------- */
    /* Three rows, and in each row a mark, a string and — on the selected row —
       a Tab glyph. Everything a ranked list usually carries is absent on
       purpose: the order is the ranking, and a count beside a row is a number
       to be priced before a keypress that saves a quarter of a second. */
    .clist { margin-top: 6px; width: max-content; min-width: 262px;
             font-family: MONOSTACK; font-size: 12px; padding: 4px;
             border-radius: 9px; background: var(--panel-bg);
             border: 0.5px solid var(--separator);
             box-shadow: 0 10px 26px rgba(0,0,0,0.18), 0 1px 3px rgba(0,0,0,0.10); }
    /* Every row is full-strength label: the selected one is told apart by the
       mark and the Tab glyph, which is the whole of what a row may carry. */
    .crow { display: flex; align-items: center; gap: 8px; height: 26px; padding: 0 8px;
            border-radius: 6px; color: var(--label); }
    .crow .mk { width: 11px; flex: none; display: flex; justify-content: center; }
    .crow .ct { white-space: nowrap; }
    .crow .cg { margin-left: auto; padding-left: 16px; font-size: 10px; color: var(--label-3); }

    /* ---- the strip along the bottom of a window -------------------------- */
    .strip { height: 27px; flex: none; display: flex; align-items: center; gap: 9px;
             padding: 0 11px; background: var(--strip-bg);
             border-top: 0.5px solid var(--separator);
             font-family: MONOSTACK; font-size: 11px; color: var(--label); }
    .strip .typed { color: var(--label-2); }
    .strip .tabmark { margin-left: auto; color: var(--label-2); opacity: 0.7; }

    /* ---- the minimised dot ---------------------------------------------- */
    .mindot { display: inline-block; width: 7px; height: 7px; border-radius: 50%;
              background: var(--dot); margin-left: 7px; vertical-align: 1px; }

    /* ---- more contrast, asked for by the system -------------------------- */
    /* Not the ghost turned up: a chip with an opaque ground and a full-strength
       border, because what fails the contrast check is the greying itself. */
    .chip { display: inline-flex; align-items: center; gap: 8px; margin-left: 3px;
            padding: 1px 7px; border-radius: 5px; background: var(--chip-bg);
            border: 1px solid var(--chip-border); color: var(--chip-ink); }
    .chip .tabmark { opacity: 0.85; margin-left: 0; }
    .clist.hc { border: 1px solid var(--chip-border); box-shadow: none;
                background: var(--chip-bg); }
    .clist.hc .crow { color: var(--chip-ink); }
    .clist.hc .crow.on { background: var(--accent); color: #FFFFFF; }
    .clist.hc .crow.on .cg { color: rgba(255,255,255,0.85); }

    /* ---- the browser and the document ----------------------------------- */
    .toolbar-row { height: 40px; flex: none; display: flex; align-items: center; gap: 10px;
                   padding: 0 12px; background: var(--term-chrome);
                   border-bottom: 0.5px solid var(--separator); }
    .urlfield { flex: 1; height: 24px; border-radius: 12px; background: var(--fill);
                display: flex; align-items: center; padding: 0 12px;
                font-family: MONOSTACK; font-size: 11px; color: var(--label); }
    .page { flex: 1; padding: 20px 22px; }
    .page .blk { height: 8px; border-radius: 4px; background: var(--fill); margin-bottom: 11px; }
    .doc { padding: 22px 26px; font-size: var(--t-body); line-height: 1.85; color: var(--label); }
    .doc .h { font-size: var(--t-title3); font-weight: 600; margin: 0 0 10px; }
""".replace("MONOSTACK", MONO)


# ---- hosts ---------------------------------------------------------------
def window(inner, width, height=None, cls=""):
    size = f"width: {width}px" + (f"; height: {height}px" if height else "")
    return f'<div class="win {cls}" style="{size}">{inner}</div>'


def hostbar(title):
    return f'<div class="hostbar">{lights()}<span class="ttl">{title}</span></div>'


def terminal(lines, width=660, title="uttrflow &mdash; zsh &mdash; 80&times;24"):
    """A terminal host, whose active line is the last one handed in."""
    return window(hostbar(title) + f'<div class="tbody">{lines}</div>', width, cls="term")


PROMPT = '<span class="prompt">~/projects/uttrflow %</span> '

SCROLLBACK = (
    f'<div class="tline past">{PROMPT}swift test --filter PredictTests</div>'
    '<div class="tline past">Executed 41 tests, with 0 failures (0.42s)</div>'
)


def ghost_line(typed, completion):
    """The certain state: what was typed, the caret, then the rest at 45%."""
    return (f'<div class="tline">{PROMPT}{typed}<span class="caret"></span>'
            f'<span class="ghost">{completion}</span>'
            '<span class="tabmark">&#8677;</span></div>')


def chip_line(typed, completion):
    """The same line once the system has asked for more contrast."""
    return (f'<div class="tline">{PROMPT}{typed}<span class="caret"></span>'
            f'<span class="chip">{completion}'
            f'<span class="tabmark">&#8677;</span></span></div>')


#: Where the panel hangs: the prompt and what has been typed, in monospace
#: columns, less the row's own left padding and mark.
def offset(typed):
    return f"calc({len('~/projects/uttrflow % ') + len(typed)}ch - 27px)"


def choices(rows, hc=False, indent=None):
    """The list under the caret — a mark on the selected row, a string, a Tab glyph."""
    out = ""
    for i, text in enumerate(rows):
        on = i == 0
        mark = logo(11, fill="currentColor") if on else ""
        glyph = '<span class="cg">&#8677;</span>' if on else ""
        out += (f'<div class="crow{" on" if on else ""}"><span class="mk">{mark}</span>'
                f'<span class="ct">{text}</span>{glyph}</div>')
    style = f' style="margin-left: {indent}"' if indent else ""
    return f'<div class="clist{" hc" if hc else ""}"{style}>{out}</div>'


def browser(width=660):
    """A browser whose address bar publishes its value and no caret rectangle."""
    chevrons = ('<span style="color: var(--label-3); display:flex; gap:6px">'
                + icon('<path d="M15 5l-7 7 7 7"/>', size=15, width=1.8)
                + icon('<path d="M9 5l7 7-7 7"/>', size=15, width=1.8) + "</span>")
    page_blocks = "".join(
        f'<div class="blk" style="width: {w}%"></div>' for w in (46, 92, 86, 94, 71)
    )
    strip = ('<div class="strip">' + logo(12, fill="var(--logo-ink)")
             + '<span><span class="typed">docs.example.com/gu</span>ides/keyboard</span>'
             + '<span class="tabmark">&#8677;</span></div>')
    inner = (hostbar("Example Docs")
             + f'<div class="toolbar-row">{chevrons}'
             '<div class="urlfield">docs.example.com/gu<span class="caret"'
             ' style="margin-left:1px"></span></div></div>'
             f'<div class="page">{page_blocks}</div>{strip}')
    return window(inner, width, height=286)


def document(width=660):
    """A document, and at the end of its last line the one dot that is left."""
    inner = (hostbar("Release notes")
             + '<div class="doc"><p class="h">Release notes</p>'
             '<p style="margin: 0">Ship the build once notarisation clears, then leave the '
             'download link exactly as it is so nothing on the site has to change.</p>'
             '<p style="margin: 10px 0 0">The next thing<span class="caret"></span>'
             '<span class="mindot"></span></p></div>')
    return window(inner, width)


def artboard(title, stage, body, caption, dark):
    html = page(
        title, stage[0], stage[1],
        f"""  <div style="display: flex; flex-direction: column; align-items: center">
{body}
    <div class="caption">{caption}</div>
  </div>""",
        extra_css=SHELL_CSS + PRED_VARS + PRED_CSS,
        pad=34,
    )
    if dark:
        html = html.replace('class="stage"', 'class="stage night theme-dark"')
    return html


# ---- the five states -----------------------------------------------------
CERTAIN = (820, 500)
CHOICE = (820, 580)
MINIMISED = (820, 480)
STRIP = (820, 560)
CONTRAST = (820, 700)

ROWS = ["git commit --amend --no-edit",
        "git checkout -b release/0.4",
        "git clean -fd .build"]


def certain(dark):
    body = "    " + terminal(SCROLLBACK + ghost_line("git ch", "eckout -b release/0.4"))
    return artboard(
        "Tab to complete &mdash; certain", CERTAIN, body,
        "One candidate, far enough ahead of the rest that offering a choice would be "
        "theatre. <b>The rest of the line is drawn in the line&rsquo;s own colour at "
        "45%</b>, with a hairline Tab marker after it and nothing else &mdash; no chip, "
        "no border, no list. Tab takes it; typing another character replaces it; any "
        "other key leaves it behind without ever having interrupted anything.",
        dark)


def choice(dark):
    body = "    " + terminal(
        SCROLLBACK
        + ghost_line("git c", "ommit --amend --no-edit")
        + choices(ROWS, indent=offset("git c"))
    )
    return artboard(
        "Tab to complete &mdash; choice", CHOICE, body,
        "The leader is inline exactly as above, and the alternatives sit under the caret. "
        "<b>A row is a mark, a string and, on the selected row, a Tab glyph.</b> There are "
        "no counts, no percentages, no confidence bars and no legend of keys along the "
        "bottom: the ranking is the order, and arrow keys move the selection whether or "
        "not a strip of text says so. It should look nearly empty. That is the design.",
        dark)


def minimised(dark):
    body = "    " + document()
    return artboard(
        "Tab to complete &mdash; minimised", MINIMISED, body,
        "Dismissed once, or typing faster than the suggestion is worth reading. "
        "<b>A single seven-pixel dot at the end of the line</b> and nothing else: Tab "
        "still accepts what is behind it, and the dot is the only claim the app makes on "
        "a document it is not being asked to help with.",
        dark)


def strip(dark):
    body = "    " + browser()
    return artboard(
        "Tab to complete &mdash; window strip", STRIP, body,
        "Some fields publish their text and no caret rectangle &mdash; an address bar is "
        "the common one &mdash; and an inline ghost cannot be drawn without knowing where "
        "the caret is. <b>The suggestion goes to a thin strip pinned to the bottom edge of "
        "that window</b>, which is the third rung of the placement ladder in "
        "<i>Docs/predict-probe.md</i>. Same three parts: the mark, the text, a Tab glyph.",
        dark)


def contrast(dark):
    one = terminal(chip_line("git ch", "eckout -b release/0.4"))
    two = terminal(chip_line("git c", "ommit --amend --no-edit")
                   + choices(ROWS, hc=True, indent=offset("git c")))
    body = f"""    <div style="width: 660px">
      <p class="stack-label">Certain</p>
      {one}
      <p class="stack-label" style="margin-top: 22px">Choice</p>
      {two}
    </div>"""
    return artboard(
        "Tab to complete &mdash; more contrast", CONTRAST, body,
        "What is drawn under Increase Contrast or Reduce Transparency. The ghost measures "
        f"<b>{GHOST_L:.1f}:1</b> on light and <b>{GHOST_D:.1f}:1</b> on dark &mdash; "
        "computed by the check at the foot of this generator, and both under the 4.5:1 "
        "body text owes &mdash; so it is not dimmed further and not merely darkened: it "
        "is replaced by <b>a solid chip with an opaque ground and a full-strength "
        "border</b>, and the selection in the list becomes a fill rather than a shade.",
        dark)


# ---- contrast check ------------------------------------------------------
# Nothing else in Design measures its own colours, and this is the one artboard
# whose subject is a contrast failure, so the figure the caption prints is
# computed here rather than asserted in prose.
def _channel(value):
    v = value / 255
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4


def _rgb(colour):
    return tuple(int(colour[i:i + 2], 16) for i in (1, 3, 5))


def _luminance(rgb):
    r, g, b = (_channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def blend(fg, bg, alpha):
    """What an alpha colour actually becomes once it is over its ground."""
    f, b = _rgb(fg), _rgb(bg)
    return tuple(f[i] * alpha + b[i] * (1 - alpha) for i in range(3))


def ratio(fg, bg):
    a, b = _luminance(fg if isinstance(fg, tuple) else _rgb(fg)), _luminance(
        bg if isinstance(bg, tuple) else _rgb(bg))
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


#: What 45% of the line's colour actually measures, on each ground it is drawn
#: on. Both are under the 4.5:1 body text owes, which is state 5's whole reason.
GHOST_L = ratio(blend(TERM_INK, TERM_BG, GHOST_ALPHA), TERM_BG)
GHOST_D = ratio(blend(TERM_INK_D, TERM_BG_D, GHOST_ALPHA), TERM_BG_D)

#: Each check is (what, measured, the floor it must clear, or None to only report).
CHECKS = [
    ("ghost, light — the reason state 5 exists", GHOST_L, None),
    ("ghost, dark — the reason state 5 exists", GHOST_D, None),
    ("chip text on chip, light", ratio(CHIP_INK, CHIP_BG), 4.5),
    ("chip text on chip, dark", ratio(CHIP_INK_D, CHIP_BG_D), 4.5),
    ("chip border on terminal, light", ratio(CHIP_BORDER, TERM_BG), 3.0),
    ("chip border on terminal, dark", ratio(CHIP_BORDER_D, TERM_BG_D), 3.0),
    ("minimised dot on paper, light", ratio(DOT, "#FFFFFF"), 3.0),
    ("minimised dot on paper, dark", ratio(DOT_D, "#1E1E1E"), 3.0),
    ("selected row, more contrast", ratio("#FFFFFF", "#128077"), 4.5),
    ("list row text, light", ratio(blend("#000000", "#FFFFFF", 0.847), "#FFFFFF"), 4.5),
    ("list row text, dark", ratio(blend("#FFFFFF", "#262628", 0.851), "#262628"), 4.5),
    ("strip text, light", ratio(blend("#000000", "#F6F6F8", 0.847), "#F6F6F8"), 4.5),
    ("strip text, dark", ratio(blend("#FFFFFF", "#2C2C2F", 0.851), "#2C2C2F"), 4.5),
]


def check():
    failed = []
    for name, measured, floor in CHECKS:
        verdict = "—" if floor is None else ("ok" if measured >= floor else "FAILS")
        print(f"  {name:<42} {measured:5.2f}:1  {verdict}")
        if floor is not None and measured < floor:
            failed.append(f"{name}: {measured:.2f}:1 is under {floor}:1")
    if failed:
        raise SystemExit("contrast check failed:\n  " + "\n  ".join(failed))


written = []
for stem, build in (("Predict-Certain", certain), ("Predict-Choice", choice),
                    ("Predict-Minimised", minimised), ("Predict-Window-Strip", strip),
                    ("Predict-High-Contrast", contrast)):
    written += write_pair(stem, build)
check()
print(f"wrote {len(written)} predict artboards")
