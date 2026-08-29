from _gen_common import *

W, H = 720, 580

SET_CSS = """
    .split { display: flex; flex: 1; min-height: 0; }
    .side { width: 188px; background: var(--sidebar-bg); border-right: 0.5px solid var(--separator);
            padding: 8px; display: flex; flex-direction: column; }
    .side .sitem { display: flex; align-items: center; gap: 9px; height: 30px;
                   padding: 0 9px; border-radius: 7px; font-size: var(--t-body);
                   color: var(--label); }
    .side .sitem.on { background: var(--accent); color: #FFFFFF; }
    .side .sitem .ico { opacity: 0.65; display: flex; }
    .side .sitem.on .ico { opacity: 1; }
    .pane { flex: 1; padding: 20px 26px; overflow: hidden; }
    .pane h2 { font-size: var(--t-title2); font-weight: 700; margin: 0 0 16px; letter-spacing: -0.1px; }
    .grp { border-radius: var(--radius-card); border: 0.5px solid var(--separator);
           background: #FFFFFF; overflow: hidden; margin-bottom: 16px;
           box-shadow: 0 1px 2px rgba(0,0,0,0.03); }
    .grp .r { display: flex; align-items: center; gap: 12px; padding: 9px 13px; min-height: 40px; }
    .grp .r + .r { border-top: 0.5px solid var(--separator); }
    .grp .r .lbl { font-size: var(--t-body); }
    .grp .r .desc { font-size: var(--t-subhead); color: var(--label-2); margin-top: 2px;
                    line-height: 1.35; }
    .grp .r .right { margin-left: auto; display: flex; align-items: center; gap: 8px; flex: none; }
    .grp-title { font-size: var(--t-subhead); font-weight: 600; color: var(--label-2);
                 margin: 0 0 7px 3px; letter-spacing: 0.2px; }
    .sw { width: 38px; height: 22px; border-radius: 11px; background: var(--fill-2);
          position: relative; flex: none; }
    .sw.on { background: var(--accent-light); }
    .sw i { position: absolute; top: 2px; left: 2px; width: 18px; height: 18px;
            border-radius: 50%; background: #FFFFFF; box-shadow: 0 1px 2px rgba(0,0,0,0.22); }
    .sw.on i { left: 18px; }
    .pop { display: inline-flex; align-items: center; gap: 7px; height: 22px; padding: 0 7px 0 9px;
           border-radius: 6px; background: #FFFFFF; border: 0.5px solid rgba(0,0,0,0.16);
           box-shadow: 0 0.5px 1px rgba(0,0,0,0.07); font-size: var(--t-callout); }
    .pop .chev { color: var(--label-2); font-size: 9px; line-height: 1; }
    .seg { display: inline-flex; border-radius: 7px; background: var(--fill); padding: 2px; gap: 2px; }
    .seg span { padding: 0 11px; height: 21px; display: flex; align-items: center;
                border-radius: 5px; font-size: var(--t-callout); color: var(--label-2); }
    .seg span.on { background: #FFFFFF; color: var(--label); font-weight: 500;
                   box-shadow: 0 0.5px 1.5px rgba(0,0,0,0.14); }
    .chk { width: 15px; height: 15px; border-radius: 4px; background: var(--accent);
           display: flex; align-items: center; justify-content: center; color: #FFFFFF; flex: none; }
    .chk.off { background: transparent; border: 1px solid var(--label-3); }
    .picker { position: relative; width: 46px; height: 29px; border-radius: 5px;
               background: linear-gradient(160deg, #5B8090 0%, #334B55 100%);
               border: 0.5px solid rgba(0,0,0,0.22); flex: none; }
    .picker span { position: absolute; width: 5px; height: 5px; border-radius: 50%;
                   background: rgba(255,255,255,0.42); }
    .picker span.on { background: #FFFFFF; box-shadow: 0 0 0 2px rgba(57,208,196,0.95); }
    .callout { display: flex; gap: 9px; padding: 11px 13px; border-radius: var(--radius-card);
               background: var(--accent-wash); font-size: var(--t-subhead); color: var(--label-2);
               line-height: 1.45; }
"""

PICKER = ('<div class="picker">'
          '<span style="left:5px; bottom:5px"></span>'
          '<span style="left:50%; margin-left:-2.5px; bottom:5px"></span>'
          '<span class="on" style="right:5px; bottom:5px"></span>'
          '<span style="right:4px; top:50%; margin-top:-2.5px"></span>'
          '</div>')

NAV = [("General", GEAR), ("Languages", GLOBE), ("Dictation", MIC), ("Privacy", LOCK)]


def settings(active, pane_html):
    items = ""
    for name, glyph in NAV:
        on = " on" if name == active else ""
        items += (f'<div class="sitem{on}"><span class="ico">'
                  f'{icon(glyph, size=15, width=1.6)}</span>{name}</div>\n        ')
    return page(
        f"Settings — {active}", 800, 660,
        f"""  <div class="win" style="width: {W}px; height: {H}px">
    <div class="row" style="height: 42px; padding: 0 14px; border-bottom: 0.5px solid var(--separator);
         flex: none">{lights()}
      <div style="margin-left: 14px; font-size: var(--t-body); font-weight: 600">{active}</div>
    </div>
    <div class="split">
      <div class="side">
        {items}
      </div>
      <div class="pane">{pane_html}</div>
    </div>
  </div>""",
        extra_css=SET_CSS,
    )


def row(label, right, desc=None):
    d = f'<div class="desc">{desc}</div>' if desc else ""
    return (f'<div class="r"><div><div class="lbl">{label}</div>{d}</div>'
            f'<div class="right">{right}</div></div>')


def sw(on):
    return f'<div class="sw{" on" if on else ""}"><i></i></div>'


def pop(value):
    return f'<div class="pop">{value}<span class="chev">&#9660;</span></div>'


def seg(options, active):
    return ('<div class="seg">'
            + "".join(f'<span class="{"on" if o == active else ""}">{o}</span>' for o in options)
            + "</div>")


# ---- General -------------------------------------------------------------
general = f"""<h2>General</h2>
      <div class="grp">
        {row("Dictation shortcut",
             '<span class="key">&#8997;</span><span class="key" style="min-width:56px">Space</span>'
             '<button class="btn sm">Change</button>')}
        {row("Activation", seg(["Hold to talk", "Press to toggle"], "Hold to talk"),
             "Hold: release to finish. Toggle: press once to start, again to stop.")}
      </div>
      <p class="grp-title">Floating button</p>
      <div class="grp">
        {row("Show the floating button", sw(True),
             "Press and hold it to dictate, exactly like the shortcut.")}
        {row("Position", PICKER)}
        {row("Shrink it to a grip until I point at it", sw(True))}
        {row("Get Uttrflow out of the way while I dictate", sw(True),
             "Minimises the window so you can see what you are typing into.")}
      </div>
      <div class="grp">
        {row("Play a sound when recording starts", sw(True))}
        {row("Keep Uttrflow in the menu bar", sw(True))}
        {row("Open at login", sw(True))}
      </div>"""

# ---- Languages -----------------------------------------------------------
def lang_row(name, native, checked):
    mark = (f'<div class="chk">{icon(CHECK, size=10, width=3)}</div>' if checked
            else '<div class="chk off"></div>')
    sub = f'<div class="desc">{native}</div>' if native else ""
    return (f'<div class="r"><div class="row" style="gap:10px">{mark}'
            f'<div><div class="lbl">{name}</div>{sub}</div></div></div>')

languages = f"""<h2>Languages</h2>
      <div class="grp">
        {row("Detect the language as I speak", sw(True),
             "Recommended. Uttrflow works out which language you are speaking, including when you switch mid-sentence.")}
      </div>
      <p class="grp-title">Languages you speak</p>
      <div class="grp">
        {lang_row("English", "", True)}
        {lang_row("Hindi", "&#2361;&#2367;&#2344;&#2381;&#2342;&#2368;", True)}
        <div class="r"><div class="lbl" style="color: var(--accent)">Add Language&hellip;</div></div>
      </div>
      <div class="callout">
        <span style="flex:none; color: var(--label-3); margin-top:1px">{icon(GLOBE, size=14, width=1.7)}</span>
        <span>Mixing English and Hindi in one sentence is expected and handled. Tidying up is
        strongest in English today &mdash; Hindi gets punctuation and spacing, not rewriting.</span>
      </div>"""

# ---- Dictation -----------------------------------------------------------
dictation = f"""<h2>Dictation</h2>
      <div class="grp">
        {row("Tidy up what I say", seg(["Off", "Light", "Standard"], "Standard"),
             "Light fixes punctuation only. Standard also removes filler words and fixes grammar.")}
        {row("Use what&rsquo;s on screen for context", sw(True),
             "Helps get names, code and technical terms right. Nothing on screen is stored or sent.")}
        {row("Never change technical terms", sw(True))}
      </div>
      <p class="grp-title">Speech recognition</p>
      <div class="grp">
        <div class="r">
          <div><div class="lbl">Ready to use</div>
            <div class="desc">646 MB &middot; last checked today</div></div>
          <div class="right">
            <button class="btn sm">Check for Update</button>
            <button class="btn sm destructive">Remove</button>
          </div>
        </div>
        {row("Speed and accuracy", seg(["Faster", "Balanced", "Most accurate"], "Balanced"),
             "Balanced transcribes 30 seconds of speech in about 3 seconds on this Mac.")}
      </div>"""

# ---- Privacy -------------------------------------------------------------
privacy = f"""<h2>Privacy</h2>
      <div class="grp">
        <div class="r" style="gap: 13px; padding: 15px 13px">
          <span style="flex:none; color: var(--green)">{icon(LOCK, size=22, width=1.6)}</span>
          <div><div class="lbl" style="font-weight: 600; font-size: var(--t-title3)">
            Your words stay on your Mac</div>
            <div class="desc" style="margin-top: 3px">Recordings are never saved &mdash; audio becomes text and is gone.
            The text is kept on this Mac and deleted automatically. We never see it, and there is no
            account to tie it to.</div></div>
        </div>
      </div>
      <div class="grp">
        {row("Keep transcripts for", pop("7 days"),
             "How long the finished text stays in your history, so you can copy or re-insert it. "
             "Deleted automatically after that.")}
        <div class="r">
          <div><div class="lbl">Dictation history</div>
            <div class="desc">142 items</div></div>
          <div class="right"><button class="btn sm destructive">Clear History&hellip;</button></div>
        </div>
      </div>
      <div class="callout">
        <span style="flex:none; color: var(--label-3); margin-top:1px">{icon(GAUGE, size=14, width=1.7)}</span>
        <span>Dictation runs on this Mac, so it works with or without an internet connection.</span>
      </div>"""

for name, active, html in [
    ("Settings-General.dc.html", "General", general),
    ("Settings-Languages.dc.html", "Languages", languages),
    ("Settings-Dictation.dc.html", "Dictation", dictation),
    ("Settings-Privacy.dc.html", "Privacy", privacy),
]:
    with open(name, "w") as handle:
        handle.write(settings(active, html))
print("wrote settings artboards")
