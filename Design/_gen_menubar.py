from _gen_common import *

MB_CSS = """
    .stage.mb { background: none; display: block;
      background-image: radial-gradient(130% 110% at 80% 0%, #6E909E 0%, #446370 45%, #273840 100%); }
    .sect { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
            text-transform: uppercase; color: rgba(255,255,255,0.5); margin: 0 0 12px; }
    .bar {
      height: 26px; border-radius: 8px; display: flex; align-items: center;
      gap: 14px; padding: 0 12px;
      background: rgba(255,255,255,0.14);
      backdrop-filter: blur(20px) saturate(160%);
      -webkit-backdrop-filter: blur(20px) saturate(160%);
      box-shadow: inset 0 0.5px 0 rgba(255,255,255,0.22);
      color: rgba(255,255,255,0.86);
    }
    .bar .other { opacity: 0.42; }
    .tile { display: flex; flex-direction: column; gap: 9px; }
    .tile .cap { font-size: var(--t-footnote); color: rgba(255,255,255,0.58); }
    .menu {
      width: 268px; border-radius: 11px; padding: 5px;
      background: rgba(250,250,253,0.72);
      backdrop-filter: blur(34px) saturate(180%);
      -webkit-backdrop-filter: blur(34px) saturate(180%);
      box-shadow: 0 16px 44px rgba(0,0,0,0.34), 0 0 0 0.5px rgba(0,0,0,0.14),
                  inset 0 1px 0 rgba(255,255,255,0.5);
      color: rgba(0,0,0,0.847);
    }
    .mi { height: 24px; display: flex; align-items: center; gap: 8px;
          padding: 0 9px; border-radius: 6px; font-size: var(--t-body); }
    .mi .sc { margin-left: auto; color: rgba(0,0,0,0.36); font-size: var(--t-body); }
    .mi.hi { background: var(--accent); color: #FFFFFF; }
    .mi.hi .sc { color: rgba(255,255,255,0.72); }
    .mi.dis { color: rgba(0,0,0,0.30); }
    .mi.tall { height: 30px; }
    .msep { height: 0.5px; background: rgba(0,0,0,0.12); margin: 5px 9px; }
    .mhdr { font-size: var(--t-footnote); font-weight: 600; letter-spacing: 0.3px;
            text-transform: uppercase; color: rgba(0,0,0,0.32); padding: 6px 9px 3px; }
    .trunc { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .statusdot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
"""

REC_GLYPH = ('<path d="M12 3.5a3 3 0 0 0-3 3v5a3 3 0 0 0 6 0v-5a3 3 0 0 0-3-3z" fill="currentColor" '
             'stroke="none"/><path d="M5.5 10.5v1a6.5 6.5 0 0 0 13 0v-1"/><path d="M12 18v3"/>')

ICON_STATES = [
    ("Idle", icon(MIC, size=17, width=1.6), ""),
    ("Listening", icon(REC_GLYPH, size=17, width=1.6, stroke="#FF383C"),
     '<span class="statusdot" style="background:#FF383C; margin-left:-9px; margin-top:-12px"></span>'),
    ("Processing", icon(SPARKLE, size=17, width=1.5), ""),
    ("Needs attention", icon(MIC, size=17, width=1.6),
     '<span class="statusdot" style="background:#FF8D28; margin-left:-9px; margin-top:-12px"></span>'),
]

tiles = ""
for cap, glyph, badge in ICON_STATES:
    tiles += f"""      <div class="tile">
        <div class="bar" style="width: 152px">
          <span class="other">{icon(GLOBE, size=15, width=1.5)}</span>
          <span class="other">{icon(CLOCK, size=15, width=1.5)}</span>
          <span style="display:flex; align-items:center">{glyph}{badge}</span>
          <span class="other" style="margin-left:auto; font-size:11px">9:41</span>
        </div>
        <div class="cap">{cap}</div>
      </div>\n"""


def menu(rows):
    return f'<div class="menu">{rows}</div>'


READY_MENU = menu(f"""
      <div class="mi dis"><span class="statusdot" style="background:#34C759"></span>
        Ready</div>
      <div class="msep"></div>
      <div class="mi hi">Start Dictation<span class="sc">&#8997;Space</span></div>
      <div class="mhdr">Recent</div>
      <div class="mi"><span class="trunc">Hey John, I&rsquo;ll probably be about 20 minutes late&hellip;</span></div>
      <div class="mi"><span class="trunc">The deployment is still running, so I&rsquo;ll&hellip;</span></div>
      <div class="msep"></div>
      <div class="mi">Open Uttrflow<span class="sc">&#8984;0</span></div>
      <div class="mi">Settings&hellip;<span class="sc">&#8984;,</span></div>
      <div class="msep"></div>
      <div class="mi">Quit Uttrflow<span class="sc">&#8984;Q</span></div>""")

ATTENTION_MENU = menu(f"""
      <div class="mi tall" style="color:#C2560C"><span class="statusdot" style="background:#FF8D28"></span>
        Microphone access is turned off</div>
      <div class="mi" style="color: var(--accent)">Open System Settings&hellip;</div>
      <div class="msep"></div>
      <div class="mi dis">Start Dictation<span class="sc">&#8997;Space</span></div>
      <div class="mhdr">Recent</div>
      <div class="mi"><span class="trunc">Hey John, I&rsquo;ll probably be about 20 minutes late&hellip;</span></div>
      <div class="msep"></div>
      <div class="mi">Open Uttrflow<span class="sc">&#8984;0</span></div>
      <div class="mi">Settings&hellip;<span class="sc">&#8984;,</span></div>
      <div class="msep"></div>
      <div class="mi">Quit Uttrflow<span class="sc">&#8984;Q</span></div>""")

body = f"""  <div>
    <p class="sect">Menu bar icon</p>
    <div class="row" style="gap: 18px; margin-bottom: 34px">
{tiles}    </div>

    <p class="sect">Menu</p>
    <div class="row" style="gap: 40px; align-items: flex-start">
      <div>
        {READY_MENU}
        <div style="font-size: var(--t-footnote); color: rgba(255,255,255,0.55);
             margin-top: 12px; width: 268px; line-height: 1.5">
          Normal. Recent results can be re-inserted or copied without opening the window.
        </div>
      </div>
      <div>
        {ATTENTION_MENU}
        <div style="font-size: var(--t-footnote); color: rgba(255,255,255,0.55);
             margin-top: 12px; width: 268px; line-height: 1.5">
          Something needs fixing. The problem and its one fix sit at the top; dictation
          is disabled rather than silently failing.
        </div>
      </div>
    </div>
  </div>"""

with open("MenuBar.dc.html", "w") as handle:
    handle.write(
        page("Menu bar", 700, 620, body, extra_css=MB_CSS, pad=36).replace(
            'class="stage"', 'class="stage mb"'
        )
    )
print("wrote MenuBar.dc.html")
