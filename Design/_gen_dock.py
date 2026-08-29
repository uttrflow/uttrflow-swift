from _gen_common import *

DOCK_CSS = """
    .stage.dock { background: none; display: block;
      background-image: radial-gradient(130% 110% at 15% 0%, #6E97A8 0%, #466673 45%, #2B4049 100%); }
    .col-h { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
             text-transform: uppercase; color: rgba(255,255,255,0.55); margin-bottom: 14px; }
    .state-label { width: 96px; flex: none; text-align: right; padding-right: 20px; }
    .state-label .n { font-size: var(--t-callout); color: rgba(255,255,255,0.86); }
    .state-label .d { font-size: var(--t-footnote); color: rgba(255,255,255,0.45); margin-top: 2px; }
    .slot { width: 286px; display: flex; justify-content: flex-end; }
    .glass {
      border-radius: 22px;
      backdrop-filter: blur(28px) saturate(180%); -webkit-backdrop-filter: blur(28px) saturate(180%);
      background: rgba(248,248,252,0.66); color: rgba(0,0,0,0.847);
      box-shadow: 0 12px 34px rgba(0,0,0,0.34), 0 0 0 0.5px rgba(255,255,255,0.16),
                  inset 0 1px 0 rgba(255,255,255,0.34);
    }
    .glass.dark { background: rgba(38,38,44,0.66); color: rgba(255,255,255,0.90);
      box-shadow: 0 12px 34px rgba(0,0,0,0.44), 0 0 0 0.5px rgba(255,255,255,0.11),
                  inset 0 1px 0 rgba(255,255,255,0.15); }
    .grip { width: 9px; height: 46px; border-radius: 5px; display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 3px; }
    .grip i { width: 3px; height: 3px; border-radius: 50%; background: currentColor; opacity: 0.5; }
    .orb { width: 44px; height: 44px; border-radius: 50%; display: flex;
           align-items: center; justify-content: center; }
    .hint { height: 34px; border-radius: 17px; display: flex; align-items: center; gap: 8px;
            padding: 0 15px; font-size: var(--t-body); }
    .pill { height: 52px; border-radius: 26px; display: flex; align-items: center; gap: 12px;
            padding: 0 18px; width: 100%; }
    .pill .t { font-size: var(--t-body); font-weight: 500; }
    .pill .s { font-size: var(--t-footnote); opacity: 0.58; margin-top: 2px; }
    .wave { display: flex; align-items: center; gap: 3px; height: 26px; }
    .wave i { width: 3px; border-radius: 2px; background: var(--accent-2-deep); opacity: 0.9;
              display: block; }
    .dark .wave i { background: var(--accent-2); }
    .rec-dot { width: 9px; height: 9px; border-radius: 50%; background: #FF383C; flex: none;
               box-shadow: 0 0 0 4px rgba(255,56,60,0.22); }
    .badge { width: 30px; height: 30px; border-radius: 50%; flex: none; display: flex;
             align-items: center; justify-content: center; color: #FFFFFF; }
    .shimmer { height: 6px; border-radius: 3px; overflow: hidden; background: rgba(128,128,140,0.26); }
    .shimmer > i { display: block; height: 100%; width: 45%; border-radius: 3px;
      background: linear-gradient(90deg, rgba(57,208,196,0) 0%, var(--accent-light) 45%,
        var(--accent-2) 100%); }
    .glass .accented { color: var(--accent); }
    .glass.dark .accented { color: var(--accent-dark); }
    .ping { position: relative; }
    .ping::after { content: ""; position: absolute; inset: -9px; border-radius: 50%;
      border: 1.5px solid rgba(255,255,255,0.34); }
    .drow { display: flex; align-items: center; margin-bottom: 19px; }
    .kbd { display: inline-flex; align-items: center; justify-content: center; height: 20px;
           padding: 0 6px; border-radius: 5px; background: rgba(120,120,130,0.20);
           font-size: var(--t-footnote); font-weight: 600; }
"""

BARS = [7, 13, 20, 11, 24, 16, 9, 18, 22, 12, 6, 15, 21, 10, 8, 17, 11]


def wave():
    return '<div class="wave">' + "".join(f'<i style="height:{h}px"></i>' for h in BARS) + "</div>"


RESTING = '<div class="glass{d} grip"><i></i><i></i><i></i><i></i><i></i></div>'

HOVER = """<div class="row" style="gap: 9px">
          <div class="glass{d} hint">Dictate <span class="kbd">&#8997;Space</span></div>
          <div class="glass{d} orb">{mic}</div>
        </div>"""

LISTENING = """<div class="glass{d} pill ping">
          <span class="rec-dot"></span>
          <div style="flex:1">{wave}</div>
          <div style="font-size: var(--t-footnote); opacity: 0.55;
               font-variant-numeric: tabular-nums">0:04</div>
        </div>"""

PROCESSING = """<div class="glass{d} pill">
          <span class="accented" style="flex:none">{sparkle}</span>
          <div style="flex:1"><div class="t">Tidying up&hellip;</div>
            <div class="shimmer" style="margin-top:7px"><i></i></div></div>
        </div>"""

INSERTED = """<div class="glass{d} pill">
          <span class="badge" style="background:#34C759">{check}</span>
          <div style="flex:1"><div class="t">Inserted into Slack</div>
            <div class="s">&ldquo;Hey John, I&rsquo;ll probably be about 20 minutes late&hellip;&rdquo;</div></div>
        </div>"""

ERROR = """<div class="glass{d} pill">
          <span class="badge" style="background:#FF8D28">{warn}</span>
          <div style="flex:1"><div class="t">Nowhere to type</div>
            <div class="s">Copied to the clipboard instead</div></div>
          <button class="btn sm" style="flex:none">Paste</button>
        </div>"""

STATES = [
    ("Resting", "always there, ignorable", RESTING),
    ("Pointed at", "reminds you of the key", HOVER),
    ("Listening", "a soft tick, then bars", LISTENING),
    ("Processing", "about a second", PROCESSING),
    ("Inserted", "fades after 2s", INSERTED),
    ("Nowhere to type", "waits for you", ERROR),
]


def fill(tpl, dark):
    return tpl.format(
        d=" dark" if dark else "",
        mic=icon(MIC, size=21, width=1.6),
        wave=wave(),
        sparkle=icon(SPARKLE, size=20, width=1.5),
        check=icon(CHECK, size=16, width=2.2),
        warn=icon(WARN, size=15, width=2),
    )


rows = ""
for name, desc, tpl in STATES:
    rows += f"""      <div class="drow">
        <div class="state-label"><div class="n">{name}</div><div class="d">{desc}</div></div>
        <div class="slot">{fill(tpl, False)}</div>
        <div style="width: 36px"></div>
        <div class="slot">{fill(tpl, True)}</div>
      </div>\n"""

body = f"""  <div style="padding: 4px 0 0">
    <div class="row" style="margin-bottom: 15px">
      <div style="width: 96px"></div>
      <div style="width: 286px" class="col-h">On a light desktop</div>
      <div style="width: 36px"></div>
      <div style="width: 286px" class="col-h">On a dark desktop</div>
    </div>
{rows}    <div style="margin-left: 96px; width: 608px; font-size: var(--t-callout);
         color: rgba(255,255,255,0.52); line-height: 1.55">
      One thing, parked at the edge of the screen, growing rightwards from its anchor. It never
      takes focus, so the app you are dictating into stays active throughout. Press and hold the
      button, or hold the shortcut &mdash; both do the same thing and both start with the same
      soft tick so you know it heard you before you start talking.
    </div>
  </div>"""

with open("Dock-States.dc.html", "w") as handle:
    handle.write(
        page("Dock states", 900, 780, body, extra_css=DOCK_CSS, pad=34).replace(
            'class="stage"', 'class="stage dock"'
        )
    )
print("wrote Dock-States.dc.html")
