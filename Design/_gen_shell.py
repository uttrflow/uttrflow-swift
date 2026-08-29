"""The application shell: the persistent sidebar every main-window screen sits
in, and the light/dark pair each artboard is drawn as.

Dark is not a filter over the light artboard. It re-declares the same tokens
`_gen_common.TOKENS` declares, on `.theme-dark`, so every screen built here
inherits both appearances from one place and neither can drift from the other.
"""
from _gen_common import *

W, H = 900, 620
STAGE_W, STAGE_H = 980, 700

# ---- glyphs the shared set does not carry --------------------------------
BOOK = ('<path d="M5 5A2 2 0 0 1 7 3h12v14.6H7A2 2 0 0 0 5 19.6z"/>'
        '<path d="M5 19.6A2 2 0 0 1 7 17.6h12V21H7a2 2 0 0 1-2-1.4z"/>'
        '<path d="M8.6 7.4h6.6M8.6 10.6h4.4"/>')
SWAP = ('<path d="M4 8.6h13.4"/><path d="M14 5.2 17.4 8.6 14 12"/>'
        '<path d="M20 15.4H6.6"/><path d="M10 12 6.6 15.4 10 18.8"/>')
CHART = ('<path d="M4 20h16"/><path d="M7.6 17V11.4"/><path d="M12 17V6.6"/>'
         '<path d="M16.4 17v-3.8"/>')
SNIPPET = ('<rect x="9" y="3.4" width="11" height="9.2" rx="2.2"/>'
           '<path d="M15 15.6v2.2a2.2 2.2 0 0 1-2.2 2.2H6.2A2.2 2.2 0 0 1 4 17.8V9.8'
           'a2.2 2.2 0 0 1 2.2-2.2h2.2"/>')
PERSON = '<circle cx="12" cy="8.2" r="3.6"/><path d="M4.9 20a7.1 7.1 0 0 1 14.2 0"/>'
COPY = ('<rect x="9" y="9" width="11" height="11" rx="2.2"/>'
        '<path d="M15 6.4V6.2A2.2 2.2 0 0 0 12.8 4H6.2A2.2 2.2 0 0 0 4 6.2v6.6'
        'A2.2 2.2 0 0 0 6.2 15h.2"/>')
REPEAT = ('<path d="M4.6 11.4A7.4 7.4 0 0 1 17.2 6.6L20 9.2"/><path d="M20 4.4v4.8h-4.8"/>'
          '<path d="M19.4 12.6A7.4 7.4 0 0 1 6.8 17.4L4 14.8"/><path d="M4 19.6v-4.8h4.8"/>')
FLAG = '<path d="M6 21V4"/><path d="M6 4.8h11l-2.2 3.7L17 12.2H6"/>'
MORE = ('<circle cx="5.6" cy="12" r="1.5" fill="currentColor" stroke="none"/>'
        '<circle cx="12" cy="12" r="1.5" fill="currentColor" stroke="none"/>'
        '<circle cx="18.4" cy="12" r="1.5" fill="currentColor" stroke="none"/>')
PLUS = '<path d="M12 5.2v13.6M5.2 12h13.6"/>'
UNDO = ('<path d="M4 9.4h9.6A5.6 5.6 0 0 1 19.2 15v0a5.6 5.6 0 0 1-5.6 5.6H8.2"/>'
        '<path d="M7.6 5.2 3.4 9.4l4.2 4.2"/>')
WIFI_OFF = ('<path d="M2.4 8.8A15.2 15.2 0 0 1 7.6 5.8"/>'
            '<path d="M21.6 8.8a15.2 15.2 0 0 0-8.4-3.6"/>'
            '<path d="M5.9 12.7A10 10 0 0 1 9 11"/>'
            '<path d="M18.1 12.7a10 10 0 0 0-2.9-1.7"/>'
            '<path d="M9.3 16.3a4.7 4.7 0 0 1 5.1-.4"/>'
            '<path d="M12 20v.1"/><path d="M3.2 3.2 20.8 20.8"/>')
SEARCH_GLYPH = '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/>'

# ---- the shell -----------------------------------------------------------
SHELL_CSS = """
    /* Surfaces the shared tokens do not name, so the dark block can swap them. */
    :root {
      --card-bg: #FFFFFF;
      --control-bg: #FFFFFF;
      --control-border: rgba(0,0,0,0.16);
      --accent-text: var(--accent);
      --hover-bg: rgba(0,0,0,0.038);
    }
    /* Dark mode, declared as its own set of the same tokens. */
    .theme-dark {
      --label: rgba(255,255,255,0.851);
      --label-2: rgba(255,255,255,0.549);
      --label-3: rgba(255,255,255,0.278);
      --label-4: rgba(255,255,255,0.098);
      --separator: rgba(255,255,255,0.129);
      --window-bg: #1E1E1E;
      /* The mark reverses on dark: chalk, not the ink it uses on white. */
      --logo-ink: #F2F1EC;
      --sidebar-bg: rgba(44,44,47,0.94);
      --fill: rgba(255,255,255,0.075);
      --fill-2: rgba(255,255,255,0.13);
      --accent-wash: rgba(18,128,119,0.22);
      --accent-tint: rgba(18,128,119,0.46);
      --card-bg: #262628;
      --control-bg: #3A3A3D;
      --control-border: rgba(255,255,255,0.15);
      --accent-text: var(--accent-dark);
      --hover-bg: rgba(255,255,255,0.062);
      color: var(--label);
    }
    .stage.night { background: #1B1B21;
      background-image: radial-gradient(120% 120% at 20% 0%, #3E3E4A 0%, #26262F 58%, #16161B 100%); }
    .theme-dark .win { box-shadow: 0 22px 60px rgba(0,0,0,0.55), 0 2px 6px rgba(0,0,0,0.40),
                                   0 0 0 0.5px rgba(255,255,255,0.10); }
    .theme-dark .btn { background: var(--control-bg); border-color: var(--control-border);
                       color: var(--label); box-shadow: 0 0.5px 1px rgba(0,0,0,0.45); }
    .theme-dark .btn.primary { background: var(--accent); color: #FFFFFF; border-color: transparent; }
    .theme-dark .btn.plain { background: transparent; border-color: transparent;
                             box-shadow: none; color: var(--accent-dark); }
    .theme-dark .btn.destructive { color: var(--red); }
    .theme-dark .key { background: var(--control-bg); border-color: rgba(255,255,255,0.20);
      box-shadow: 0 1px 0 rgba(0,0,0,0.45), inset 0 -1px 0 rgba(255,255,255,0.06);
      color: var(--label); }
    .theme-dark a { color: var(--accent-dark); }

    /* window furniture */
    .split { display: flex; flex: 1; min-height: 0; }
    .side { width: 204px; flex: none; background: var(--sidebar-bg);
            border-right: 0.5px solid var(--separator); padding: 6px 8px 10px;
            display: flex; flex-direction: column; }
    .brand { display: flex; align-items: center; gap: 8px; height: 30px; padding: 0 7px;
             margin: 2px 0 8px; }
    .brand .n { font-size: var(--t-body); font-weight: 600; letter-spacing: -0.1px; }
    .sitem { display: flex; align-items: center; gap: 9px; height: 28px; padding: 0 9px;
             border-radius: 7px; font-size: var(--t-body); color: var(--label);
             margin-bottom: 1px; }
    .sitem.on { background: var(--accent); color: #FFFFFF; }
    .sitem .ico { opacity: 0.62; display: flex; }
    .sitem.on .ico { opacity: 1; }
    .sitem .tail { margin-left: auto; font-size: var(--t-footnote); color: var(--label-3);
                   font-variant-numeric: tabular-nums; }
    .sitem.on .tail { color: rgba(255,255,255,0.75); }
    .recent { margin-top: auto; padding: 0 3px; }
    .recent .cap { font-size: var(--t-footnote); font-weight: 600; letter-spacing: 0.3px;
                   text-transform: uppercase; color: var(--label-3); margin: 0 0 6px 5px; }
    .recent .box { border-radius: 8px; background: var(--fill); padding: 8px 9px; }
    .recent .box .w { font-size: var(--t-footnote); color: var(--label-2);
                      display: flex; gap: 5px; }
    .recent .box .t { font-size: var(--t-subhead); line-height: 1.4; margin-top: 4px; }
    .sidehint { display: flex; align-items: center; gap: 5px; margin: 11px 5px 2px;
                font-size: var(--t-footnote); color: var(--label-3); }

    .pane { flex: 1; min-width: 0; display: flex; flex-direction: column;
            background: var(--window-bg); }
    .toolbar { height: 44px; display: flex; align-items: center; gap: 10px; padding: 0 18px;
               border-bottom: 0.5px solid var(--separator); flex: none; }
    .toolbar h2 { font-size: var(--t-title3); font-weight: 600; margin: 0; }
    .tools { margin-left: auto; display: flex; align-items: center; gap: 8px; }
    .content { flex: 1; min-height: 0; padding: 18px 22px 14px; overflow: hidden;
               display: flex; flex-direction: column; }

    /* shared content furniture */
    .card { border-radius: var(--radius-card); border: 0.5px solid var(--separator);
            background: var(--card-bg); box-shadow: 0 1px 2px rgba(0,0,0,0.03); }
    .daylabel { font-size: var(--t-subhead); font-weight: 600; color: var(--label-2);
                margin: 0 0 7px 3px; }
    .search { display: flex; align-items: center; gap: 7px; height: 24px; padding: 0 9px;
              border-radius: 7px; background: var(--fill); font-size: var(--t-callout);
              color: var(--label-3); width: 180px; }
    .pop { display: inline-flex; align-items: center; gap: 7px; height: 24px;
           padding: 0 7px 0 9px; border-radius: 6px; background: var(--control-bg);
           border: 0.5px solid var(--control-border); box-shadow: 0 0.5px 1px rgba(0,0,0,0.07);
           font-size: var(--t-callout); color: var(--label); }
    .pop .chev { color: var(--label-2); font-size: 9px; line-height: 1; }
    .appicon { width: 15px; height: 15px; border-radius: 4px; flex: none; display: flex;
               align-items: center; justify-content: center; color: #FFFFFF; font-size: 8px;
               font-weight: 700; }
    .iconbtn { width: 24px; height: 24px; border-radius: 6px; display: flex; flex: none;
               align-items: center; justify-content: center; color: var(--label-2);
               background: var(--control-bg); border: 0.5px solid var(--control-border);
               box-shadow: 0 0.5px 1px rgba(0,0,0,0.06); }
    .theme-dark .iconbtn { box-shadow: 0 0.5px 1px rgba(0,0,0,0.4); }
    .pill { display: inline-flex; align-items: center; gap: 4px; height: 16px; padding: 0 6px;
            border-radius: 5px; font-size: var(--t-footnote); font-weight: 500;
            background: var(--fill); color: var(--label-2); white-space: nowrap; }
    .pill.accent { background: var(--accent-wash); color: var(--accent-text); }
    .pill.warn { background: rgba(255,141,40,0.16); color: #A85300; }
    .theme-dark .pill.warn { color: #FFB067; }
    .pill.good { background: rgba(52,199,89,0.16); color: #1E7B36; }
    .theme-dark .pill.good { color: #5EDC80; }
    .stat .v { font-size: var(--t-title1); font-weight: 600; letter-spacing: -0.4px;
               font-variant-numeric: tabular-nums; }
    .stat .k { font-size: var(--t-subhead); color: var(--label-2); margin-top: 2px; }
    .stat .c { font-size: var(--t-footnote); color: var(--label-3); margin-top: 5px;
               line-height: 1.4; }
    .foot { font-size: var(--t-footnote); color: var(--label-3); line-height: 1.5;
            margin-top: auto; padding-top: 12px; }
    .empty { flex: 1; display: flex; flex-direction: column; align-items: center;
             justify-content: center; text-align: center; padding: 0 56px; }
    .empty .ring { width: 82px; height: 82px; border-radius: 50%; display: flex;
                   align-items: center; justify-content: center; color: var(--accent-text);
                   background: var(--accent-wash); border: 1px solid var(--accent-tint); }
    .empty h3 { font-size: var(--t-title2); font-weight: 600; margin: 18px 0 0;
                letter-spacing: -0.2px; }
    .empty p { font-size: var(--t-body); color: var(--label-2); margin: 9px 0 0;
               line-height: 1.5; max-width: 410px; text-wrap: pretty; }
    .chips { display: flex; gap: 8px; margin-top: 20px; }
    .chip { border-radius: 8px; background: var(--fill); padding: 7px 13px; text-align: center; }
    .chip .cv { font-size: var(--t-title3); font-weight: 600; font-variant-numeric: tabular-nums; }
    .chip .ck { font-size: var(--t-footnote); color: var(--label-2); margin-top: 1px; }
    .callout { display: flex; gap: 9px; padding: 10px 12px; border-radius: var(--radius-card);
               background: var(--accent-wash); font-size: var(--t-subhead); color: var(--label-2);
               line-height: 1.45; }

    /* table idiom, used by Dictionary / Corrections / Snippets */
    .th { display: flex; gap: 10px; padding: 6px 13px; font-size: var(--t-footnote);
          font-weight: 600; letter-spacing: 0.2px; color: var(--label-3);
          text-transform: uppercase; border-bottom: 0.5px solid var(--separator); }
    .tr { display: flex; gap: 10px; align-items: center; padding: 8px 13px;
          font-size: var(--t-callout); }
    .tr + .tr { border-top: 0.5px solid var(--separator); }
    .tr.hover { background: var(--hover-bg); }
    .tr.retired { opacity: 0.48; }
    .num { font-variant-numeric: tabular-nums; text-align: right; }
"""

APPS = {
    "Slack": ("#4A154B", "S"),
    "Code": ("#0F6CBD", "V"),
    "Notes": ("#1D6F42", "N"),
    "Mail": ("#D93025", "M"),
}

NAV = [
    ("Dictation", MIC), ("History", CLOCK), ("Dictionary", BOOK), ("Corrections", SWAP),
    ("Insights", CHART), ("Snippets", SNIPPET), ("Style", SPARKLE), ("Diagnostics", GAUGE),
    ("Settings", GEAR), ("Account", PERSON),
]

RECENT = """<div class="recent">
          <p class="cap">Most recent</p>
          <div class="box">
            <div class="w"><span>4:12 PM</span><span>&middot;</span><span>Slack</span></div>
            <div class="t">&ldquo;Hey John, I&rsquo;ll probably be about 20 minutes late to
              the meeting&hellip;&rdquo;</div>
          </div>
        </div>"""

RECENT_NONE = """<div class="recent">
          <p class="cap">Most recent</p>
          <div class="box">
            <div class="w"><span>Yesterday</span><span>&middot;</span><span>6:58 PM</span></div>
            <div class="t" style="color: var(--label-2)">&ldquo;Bhai kal subah call kar
              lenge, aaj bahut late ho gaya.&rdquo;</div>
          </div>
        </div>"""

RECENT_NEVER = """<div class="recent">
          <p class="cap">Most recent</p>
          <div class="box">
            <div class="t" style="color: var(--label-3)">Nothing yet. Your last dictation
              shows up here.</div>
          </div>
        </div>"""


def sidebar(active, recent=RECENT, tails=None):
    tails = tails or {}
    items = ""
    for name, glyph in NAV:
        on = " on" if name == active else ""
        tail = f'<span class="tail">{tails[name]}</span>' if name in tails else ""
        items += (f'<div class="sitem{on}"><span class="ico">'
                  f'{icon(glyph, size=15, width=1.6)}</span>{name}{tail}</div>\n        ')
    return f"""<div class="side">
        <div style="height: 26px; display: flex; align-items: center; padding: 0 4px">{lights()}</div>
        <div class="brand">{logo(20)}<span class="n">Uttrflow</span></div>
        {items}
        {recent}
        <div class="sidehint"><span class="key" style="height:17px; min-width:17px; padding:0 4px;
          font-size:9px">&#8997;</span><span class="key" style="height:17px; min-width:17px;
          padding:0 5px; font-size:9px">Space</span><span>Hold anywhere</span></div>
      </div>"""


def app_window(active, toolbar_tools, content, dark, recent=RECENT, tails=None, extra_css=""):
    """One main-window artboard, in one appearance."""
    html = page(
        f"Uttrflow &mdash; {active}", STAGE_W, STAGE_H,
        f"""  <div class="win" style="width: {W}px; height: {H}px">
    <div class="split">
      {sidebar(active, recent, tails)}
      <div class="pane">
        <div class="toolbar"><h2>{active}</h2>{toolbar_tools}</div>
        <div class="content">{content}</div>
      </div>
    </div>
  </div>""",
        extra_css=SHELL_CSS + extra_css,
    )
    if dark:
        html = html.replace('class="stage"', 'class="stage night theme-dark"')
    return html


def tools(*bits):
    return '<div class="tools">' + "".join(bits) + "</div>" if bits else ""


def searchbox(placeholder="Search"):
    return f'<div class="search">{icon(SEARCH_GLYPH, size=13, width=1.7)}{placeholder}</div>'


def pop(value):
    return f'<div class="pop">{value}<span class="chev">&#9660;</span></div>'


def addbtn(label):
    return (f'<button class="btn sm">{icon(PLUS, size=11, width=2)}'
            f'<span>{label}</span></button>')


def appchip(name):
    bg, letter = APPS[name]
    return (f'<span class="appicon" style="background:{bg}">{letter}</span>'
            f'<span>{name}</span>')


# ---- provider marks ------------------------------------------------------
# Two of these three are stand-ins and must not be shipped.
#
# Apple's is fine: `apple.logo` is an SF Symbol, so the app draws the system's
# own glyph and there is nothing to supply.
#
# Google's and GitHub's are not, and no amount of care with the paths below
# would make them so — both providers require their own file:
#
#   Google  developers.google.com/identity/branding-guidelines
#           "you can't change the size or color of the Google 'G' logo"; it
#           "must be the standard color version"; monochrome, custom or
#           outdated icons are all listed as don'ts, and the icon may not be
#           used without a button boundary and text. Pre-approved buttons ship
#           as PNG and SVG in signin-assets.zip. The button *chrome* is
#           published as hex and is honoured on the artboard (see _gen_signin);
#           the mark is not ours to draw.
#
#   GitHub  brand.github.com/foundations/logo
#           "Don't compress, distort, skew, stretch, or alter the logo in any
#           way." White, black, and in a few cases grey or green, are the only
#           permitted colours; effects and gradients are prohibited. The mark
#           is a registered trademark and the official package is
#           GitHub_Logos.zip.
#
# So the paths below exist to make the artboard readable and for no other
# reason. What has to be placed in `Resources/` before those buttons ship is
# reported with the design, not guessed at here.
def google_mark(size=16):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" aria-label="Google">'
            '<path fill="#4285F4" d="M23.5 12.27c0-.85-.08-1.67-.22-2.45H12v4.63h6.45a5.52 5.52 0 0 1-2.39 3.62v3h3.87c2.26-2.09 3.57-5.17 3.57-8.8z"/>'
            '<path fill="#34A853" d="M12 24c3.24 0 5.95-1.08 7.93-2.93l-3.87-3a7.19 7.19 0 0 1-10.7-3.77H1.36v3.09A12 12 0 0 0 12 24z"/>'
            '<path fill="#FBBC05" d="M5.36 14.3a7.19 7.19 0 0 1 0-4.6V6.61H1.36a12 12 0 0 0 0 10.78l4-3.09z"/>'
            '<path fill="#EA4335" d="M12 4.77c1.76 0 3.34.61 4.59 1.8l3.43-3.43C17.95 1.19 15.24 0 12 0A12 12 0 0 0 1.36 6.61l4 3.09A7.15 7.15 0 0 1 12 4.77z"/>'
            '</svg>')


def github_mark(size=16, color="currentColor"):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="{color}" '
            'aria-label="GitHub"><path d="M12 2.2a9.8 9.8 0 0 0-3.1 19.1c.49.09.67-.21.67-.47'
            'v-1.67c-2.72.6-3.3-1.31-3.3-1.31-.44-1.13-1.09-1.43-1.09-1.43-.89-.61.07-.6.07-.6'
            '.98.07 1.5 1.01 1.5 1.01.88 1.5 2.3 1.07 2.86.82.09-.64.34-1.07.62-1.32-2.18-.25'
            '-4.47-1.09-4.47-4.85 0-1.07.38-1.95 1.01-2.63-.1-.25-.44-1.25.1-2.61 0 0 .82-.26'
            '2.7 1.01a9.4 9.4 0 0 1 4.92 0c1.88-1.27 2.7-1.01 2.7-1.01.54 1.36.2 2.36.1 2.61'
            '.63.68 1.01 1.56 1.01 2.63 0 3.77-2.29 4.6-4.48 4.84.35.31.67.91.67 1.84v2.73'
            'c0 .26.18.57.68.47A9.8 9.8 0 0 0 12 2.2z"/></svg>')


def apple_mark(size=16, color="currentColor"):
    return (f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="{color}" '
            'aria-label="Apple"><path d="M17.05 12.9c-.03-2.6 2.12-3.85 2.22-3.91-1.21-1.77'
            '-3.09-2.01-3.76-2.04-1.6-.16-3.12.94-3.93.94-.81 0-2.06-.92-3.39-.9-1.74.03-3.35'
            ' 1.01-4.25 2.57-1.81 3.14-.46 7.79 1.3 10.34.86 1.25 1.89 2.65 3.24 2.6 1.3-.05'
            ' 1.79-.84 3.36-.84 1.57 0 2.01.84 3.39.81 1.4-.02 2.29-1.27 3.14-2.53.99-1.45'
            ' 1.4-2.86 1.42-2.93-.03-.01-2.72-1.04-2.74-4.11z"/><path d="M14.9 5.3c.71-.86'
            ' 1.19-2.06 1.06-3.25-1.02.04-2.26.68-2.99 1.54-.66.76-1.23 1.98-1.08 3.14'
            ' 1.14.09 2.3-.58 3.01-1.43z"/></svg>')


def write_pair(stem, build):
    """Writes `Stem.dc.html` and `Stem-Dark.dc.html` from one builder."""
    names = []
    for dark, suffix in ((False, ""), (True, "-Dark")):
        name = f"{stem}{suffix}.dc.html"
        with open(name, "w") as handle:
            handle.write(build(dark))
        names.append(name)
    return names
