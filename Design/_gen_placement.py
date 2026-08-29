from _gen_common import *

PL_CSS = """
    .stage.pl { background: #EFEFF3; display: block;
      background-image: linear-gradient(180deg, #F4F4F8 0%, #E8E8EE 100%); }
    .sect { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
            text-transform: uppercase; color: var(--label-3); margin: 0 0 4px; }
    .sect-d { font-size: var(--t-callout); color: var(--label-2); margin: 0 0 14px; }
    .screen { position: relative; border-radius: 10px; overflow: hidden;
      background-image: radial-gradient(130% 110% at 20% 0%, #6E97A8 0%, #466673 50%, #2B4049 100%);
      box-shadow: 0 4px 16px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.20); }
    .screen .mb { height: 9px; background: rgba(255,255,255,0.16); }
    .screen .app { position: absolute; border-radius: 5px; background: rgba(255,255,255,0.90);
      box-shadow: 0 3px 10px rgba(0,0,0,0.24); overflow: hidden; }
    .screen .app .tb { height: 7px; background: rgba(0,0,0,0.07); }
    .screen .app .ln { height: 3px; border-radius: 2px; background: rgba(0,0,0,0.11);
      margin: 5px 7px 0; }
    .anchor { position: absolute; width: 15px; height: 15px; border-radius: 50%;
      border: 1.5px dashed rgba(255,255,255,0.55); }
    .anchor.on { border: none; background: var(--accent-light);
      box-shadow: 0 0 0 4px rgba(57,208,196,0.42); }
    .anchor .tag { position: absolute; white-space: nowrap; font-size: 9px; font-weight: 600;
      color: rgba(255,255,255,0.80); top: 19px; left: 50%; transform: translateX(-50%); }
    .anchor.on .tag { color: #FFFFFF; }
    .minidock { position: absolute; display: flex; align-items: center; gap: 4px; }
    .minidock .orb { width: 15px; height: 15px; border-radius: 50%; background: rgba(250,250,255,0.86);
      display: flex; align-items: center; justify-content: center; color: rgba(0,0,0,0.7);
      box-shadow: 0 2px 6px rgba(0,0,0,0.28); }
    .minidock .cap { height: 15px; border-radius: 8px; background: rgba(250,250,255,0.86);
      display: flex; align-items: center; gap: 2px; padding: 0 6px;
      box-shadow: 0 2px 6px rgba(0,0,0,0.28); }
    .minidock .cap i { width: 1.5px; border-radius: 1px; background: rgba(0,0,0,0.55); display: block; }
    .minidock .cap .dot { width: 4px; height: 4px; border-radius: 50%; background: #FF383C; flex: none; }
    .grp { border-radius: var(--radius-card); border: 0.5px solid var(--separator);
           background: #FFFFFF; overflow: hidden; box-shadow: 0 1px 2px rgba(0,0,0,0.03); }
    .grp .r { display: flex; align-items: center; gap: 12px; padding: 9px 13px; min-height: 40px; }
    .grp .r + .r { border-top: 0.5px solid var(--separator); }
    .grp .desc { font-size: var(--t-subhead); color: var(--label-2); margin-top: 2px; line-height: 1.35; }
    .grp .right { margin-left: auto; flex: none; }
    .sw { width: 38px; height: 22px; border-radius: 11px; background: var(--fill-2); position: relative; }
    .sw.on { background: var(--green); }
    .sw i { position: absolute; top: 2px; left: 2px; width: 18px; height: 18px; border-radius: 50%;
            background: #FFFFFF; box-shadow: 0 1px 2px rgba(0,0,0,0.22); }
    .sw.on i { left: 18px; }
    .arrow { display: flex; align-items: center; color: var(--label-3); }
    .cap-under { font-size: var(--t-footnote); color: var(--label-2); margin-top: 9px;
                 line-height: 1.45; }
"""

SW, SH = 300, 188

# Four anchors, expressed as offsets from the screen edges.
ANCHORS = [
    ("Bottom left", "left: 14px; bottom: 16px;", False),
    ("Bottom centre", "left: 50%; margin-left: -7.5px; bottom: 16px;", False),
    ("Bottom right", "right: 14px; bottom: 16px;", True),
    ("Right edge", "right: 8px; top: 50%; margin-top: -7.5px;", False),
]


def screen(width, height, dock_html="", anchors=False, window=True):
    marks = ""
    if anchors:
        for label, pos, on in ANCHORS:
            marks += (f'<div class="anchor{" on" if on else ""}" style="{pos}">'
                      f'<span class="tag">{label}</span></div>')
    win = ""
    if window:
        win = ('<div class="app" style="left: 26px; top: 26px; width: 168px; height: 108px">'
               '<div class="tb"></div>'
               + "".join('<div class="ln" style="width: %d%%"></div>' % w
                         for w in (86, 72, 90, 60, 80)) + "</div>")
    return (f'<div class="screen" style="width: {width}px; height: {height}px">'
            f'<div class="mb"></div>{win}{marks}{dock_html}</div>')


BARS = [3, 6, 9, 5, 10, 7, 4, 8]
LIVE_DOCK = ('<div class="minidock" style="right: 12px; bottom: 14px">'
             '<div class="cap"><span class="dot"></span>'
             + "".join(f'<i style="height:{h}px"></i>' for h in BARS)
             + "</div></div>")
REST_DOCK = ('<div class="minidock" style="right: 12px; bottom: 14px">'
             f'<div class="orb">{icon(MIC, size=9, width=2)}</div></div>')

ARROW = ('<div class="arrow">'
         + icon('<path d="M4 12h15"/><path d="M14 7l5 5-5 5"/>', size=22, width=1.6)
         + "</div>")

body = f"""  <div>
    <p class="sect">Where the button sits</p>
    <p class="sect-d">Four anchors. It grows inwards from whichever edge it is parked on, so it
      never runs off the screen.</p>
    <div class="row" style="gap: 26px; align-items: flex-start">
      {screen(430, 270, anchors=True)}
      <div style="flex: 1; padding-top: 6px">
        <p class="cap-under" style="margin-top: 0">Drag the button anywhere and it snaps to the
          nearest anchor, so it cannot end up somewhere it would cover what you are working on.</p>
        <p class="cap-under">Bottom right is the default because that is the corner least likely
          to hold a text field, and it is where the cursor already is after most edits.</p>
        <p class="cap-under">On the right edge the button turns vertical and the recorder grows
          leftwards, so a wide waveform never runs off the screen.</p>
        <p class="cap-under">Pick a position in Settings &rsaquo; General, or just drag it.</p>
      </div>
    </div>

    <div style="height: 30px"></div>
    <p class="sect">Press and hold the button</p>
    <p class="sect-d">The same thing the shortcut does &mdash; a soft tick, then bars. The window
      steps aside on its own.</p>
    <div class="row" style="gap: 20px; align-items: center">
      <div>{screen(SW, SH, dock_html=REST_DOCK)}
        <p class="cap-under" style="width: {SW}px">Window open, button resting.</p></div>
      {ARROW}
      <div>{screen(SW, SH, dock_html=LIVE_DOCK, window=False)}
        <p class="cap-under" style="width: {SW}px">Held: the window minimises, the button
          becomes the recorder, and whatever was behind it takes focus.</p></div>
    </div>
  </div>"""

with open("Dock-Placement.dc.html", "w") as handle:
    handle.write(
        page("Dock placement", 900, 700, body, extra_css=PL_CSS, pad=38).replace(
            'class="stage"', 'class="stage pl"'
        )
    )
print("wrote Dock-Placement.dc.html")
