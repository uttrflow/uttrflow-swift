"""The two main-window screens that predate the sidebar.

Home is gone: the sidebar's Dictation destination is the home surface now, and
Home's three pieces went somewhere each — the "hold the key" hero became the
Dictation empty state, "last result" became the sidebar's most-recent block,
and the counters became the Dictation rail and Insights. History and
Diagnostics are unchanged in substance and simply redrawn inside the shell,
because a screen that still wore the old three-item sidebar would contradict
every artboard next to it.
"""
from _gen_shell import *

MAIN_CSS = """
    .hrow { display: flex; gap: 12px; padding: 10px 13px; }
    .hrow + .hrow { border-top: 0.5px solid var(--separator); }
    .hrow .when { width: 62px; flex: none; font-size: var(--t-footnote); color: var(--label-2);
                  font-variant-numeric: tabular-nums; padding-top: 3px; }
    .statrow { display: flex; }
    .statrow .stat { flex: 1; padding: 11px 13px; }
    .statrow .stat + .stat { border-left: 0.5px solid var(--separator); }
    .bar-track { height: 22px; border-radius: 6px; overflow: hidden; display: flex; }
    .lat { display: flex; align-items: center; gap: 12px; padding: 8px 13px;
           font-size: var(--t-callout); }
    .lat + .lat { border-top: 0.5px solid var(--separator); }
    .lat .n { font-variant-numeric: tabular-nums; }
    .swatch { width: 9px; height: 9px; border-radius: 3px; flex: none; }
"""

# ---- History -------------------------------------------------------------
HIST = [
    ("Yesterday", [
        ("6:58 PM", "Slack", "Rahul Menon",
         "Bhai kal subah call kar lenge, aaj bahut late ho gaya.", "5s"),
        ("4:20 PM", "Code", "order_service.py",
         "Create a function that takes a user ID and returns their most recent order, "
         "or None if they have never ordered.", "9s"),
        ("11:02 AM", "Notes", "Standup",
         "Kal ke standup mein main deployment ke baare mein bataunga.", "6s"),
    ]),
    ("Friday 21 August", [
        ("5:44 PM", "Mail", "Re: Q3 planning",
         "Thanks for putting this together. I have one concern about the timeline on the "
         "migration piece.", "8s"),
        ("9:15 AM", "Slack", "#engineering",
         "Deploy is out on staging, please give it a look before standup.", "4s"),
    ]),
]


def history_group(day, rows):
    body = ""
    for when, app, doc, text, dur in rows:
        body += f"""<div class="hrow">
            <span class="when">{when}</span>
            <div style="min-width:0; flex:1">
              <div style="line-height: 1.45">{text}</div>
              <div class="row" style="gap: 6px; margin-top: 5px; font-size: var(--t-footnote);
                   color: var(--label-2)">{appchip(app)}<span>&middot;</span>
                <span>{doc}</span><span>&middot;</span><span>{dur}</span></div>
            </div>
          </div>"""
    return f'<p class="daylabel">{day}</p><div class="card">{body}</div>'

history = ("".join(
    f'<div style="margin-top: {14 if i else 0}px">{history_group(day, rows)}</div>'
    for i, (day, rows) in enumerate(HIST))
    + """<div class="foot" style="text-align: center">Today is on the Dictation screen.
        Kept on this Mac for 7 days, then deleted. Recordings are never saved.
        <span style="color: var(--accent-text)">Change in Privacy settings</span></div>""")

# ---- Diagnostics ---------------------------------------------------------
STAGES = [("Transcribing", "#39D0C4", 1.90, "1.90s", "3.40s"),
          ("Tidying up", "#29C0B4", 0.68, "0.68s", "1.35s"),
          ("Inserting", "#34C759", 0.04, "0.04s", "0.12s")]
total = sum(s[2] for s in STAGES)
segments = "".join(
    f'<div style="width:{s[2] / total * 100:.1f}%; background:{s[1]}"></div>' for s in STAGES
)
lat_rows = "".join(
    f"""<div class="lat"><span class="swatch" style="background:{c}"></span>
            <span style="flex:1">{n}</span>
            <span class="n muted" style="width:86px; text-align:right; white-space:nowrap">{p50} typical</span>
            <span class="n muted" style="width:86px; text-align:right; white-space:nowrap">{p95} slowest</span>
          </div>""" for n, c, _, p50, p95 in STAGES
)

diagnostics = f"""<p class="daylabel">Time from letting go of the key to text on screen</p>
        <div class="card" style="padding: 14px">
          <div class="row" style="justify-content: space-between; margin-bottom: 9px">
            <span style="font-size: var(--t-title2); font-weight: 600;
              font-variant-numeric: tabular-nums">2.62s</span>
            <span class="muted" style="font-size: var(--t-callout)">
              for 30 seconds of speech &middot; target under 5s</span>
          </div>
          <div class="bar-track">{segments}</div>
        </div>
        <div class="card" style="margin-top: 14px">{lat_rows}</div>
        <div class="row" style="gap: 14px; margin-top: 14px; align-items: stretch">
          <div class="card statrow" style="flex: 1">
            <div class="stat"><div class="v">99.4%</div><div class="k">Heard you</div></div>
            <div class="stat"><div class="v">96.8%</div><div class="k">Typed directly</div></div>
          </div>
          <div class="card statrow" style="flex: 1">
            <div class="stat"><div class="v">78 MB</div><div class="k">Idle memory</div></div>
            <div class="stat"><div class="v">1.6 GB</div><div class="k">Peak memory</div></div>
          </div>
        </div>
        <div class="row" style="margin-top: 14px; gap: 9px">
          <span class="muted" style="font-size: var(--t-footnote); flex: 1">
            Measured on this Mac over the last 7 days. Never sent anywhere.</span>
          <button class="btn sm">Copy Diagnostics</button>
        </div>"""

written = []
for stem, active, tool_html, content in [
    ("Main-History", "History", tools(searchbox("Search history")), history),
    ("Main-Diagnostics", "Diagnostics", "", diagnostics),
]:
    written += write_pair(
        stem,
        lambda dark, a=active, t=tool_html, c=content:
            app_window(a, t, c, dark, tails={"Corrections": "7"}, extra_css=MAIN_CSS),
    )
print(f"wrote {len(written)} main window artboards")
