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
    .bar-track { height: 18px; border-radius: 5px; overflow: hidden; display: flex; }
    .lat { display: flex; align-items: center; gap: 10px; padding: 5px 11px;
           font-size: var(--t-footnote); line-height: 1.25; }
    .lat + .lat { border-top: 0.5px solid var(--separator); }
    .lat .n { font-variant-numeric: tabular-nums; }
    .swatch { width: 8px; height: 8px; border-radius: 2px; flex: none; }
    .diagverdict { display: flex; align-items: center; gap: 10px; padding: 9px 13px; }
    .diagverdict .dot { width: 7px; height: 7px; border-radius: 50%; flex: none;
                         background: #34C759; }
    .frow { display: flex; align-items: center; gap: 10px; padding: 5px 11px;
            font-size: var(--t-footnote); line-height: 1.25; }
    .frow + .frow { border-top: 0.5px solid var(--separator); }
    .frow .dot { width: 7px; height: 7px; border-radius: 50%; flex: none; }
    .frow .d { color: var(--label-2); text-align: right; }
    .diagstats { display: flex; flex-wrap: wrap; }
    .diagstats .stat { flex: 1 1 33%; min-width: 130px; padding: 7px 11px;
                        border-top: 0.5px solid var(--separator); }
    .diagstats .stat:nth-child(-n+3) { border-top: none; }
    .diagstats .v { font-size: var(--t-body); font-weight: 600;
                     font-variant-numeric: tabular-nums; }
    .diagstats .k { font-size: 10px; color: var(--label-2); margin-top: 1px; }
    .diaglabel { font-size: var(--t-footnote); font-weight: 600; color: var(--label-2);
                 margin: 8px 0 5px 3px; }
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
# Stage order, titles and colours mirror `PipelineStage.allCases` and
# `DiagnosticsPresenter.title(for:)`/`DiagnosticsPageView.colour(for:)` in
# Sources/UttrflowUX/DiagnosticsPresentation.swift and
# Sources/Uttrflow/Main/DiagnosticsPageView.swift; kept in sync by
# Scripts/design_diagnostics_contract_audit.py.
STAGE_TITLES = {
    "microphoneOpen": "Opening the microphone",
    "capture": "Recording",
    "drain": "Finishing the piece already under way",
    "transcription": "Transcribing",
    "correction": "Checking the dictionary",
    "transformation": "Tidying up",
    "expansion": "Expanding snippets",
    "insertion": "Inserting",
}
STAGE_COLOURS = {
    "microphoneOpen": "#9EDCD7", "capture": "#9EDCD7", "drain": "#9EDCD7",
    "transcription": "#39D0C4", "correction": "#128077", "transformation": "#29C0B4",
    "expansion": "#EFF8F7", "insertion": "#34C759",
}
# One row per stage something has timed: (stage, typical seconds, typical, slowest, samples).
MEASURED_STAGES = [
    ("microphoneOpen", 0.06, "0.06s", "0.14s", 42),
    ("capture", 0.02, "0.02s", "0.05s", 42),
    ("transcription", 1.42, "1.42s", "2.65s", 42),
    ("correction", 0.03, "0.03s", "0.08s", 17),
    ("transformation", 0.58, "0.58s", "1.10s", 40),
    ("insertion", 0.04, "0.04s", "0.12s", 42),
]
# Nothing has ever timed these; drawn as "Never run" rather than a false zero.
NEVER_RUN_STAGES = ["drain", "expansion"]
# One transcription per dictation, so its own sample count is what the total rests on.
DICTATIONS_TIMED = next(s[4] for s in MEASURED_STAGES if s[0] == "transcription")
FOOTNOTE = "Measured on this Mac since Uttrflow started, and never sent anywhere."

_stage_total = sum(s[1] for s in MEASURED_STAGES)
lat_segments = "".join(
    f'<div style="width:{seconds / _stage_total * 100:.1f}%; background:{STAGE_COLOURS[stage]}">'
    "</div>"
    for stage, seconds, _, _, _ in MEASURED_STAGES
)
lat_rows = "".join(
    f"""<div class="lat"><span class="swatch" style="background:{STAGE_COLOURS[stage]}"></span>
            <span style="flex:1">{STAGE_TITLES[stage]}</span>
            <span class="n muted" style="width:86px; text-align:right; white-space:nowrap">{typical} typical</span>
            <span class="n muted" style="width:86px; text-align:right; white-space:nowrap">{slowest} slowest</span>
          </div>""" for stage, _, typical, slowest, _ in MEASURED_STAGES
)
never_run_rows = "".join(
    f"""<div class="frow"><span class="dot" style="background:var(--label-4)"></span>
            <span style="flex:1">{STAGE_TITLES[stage]}</span>
            <span class="d">Never run</span></div>""" for stage in NEVER_RUN_STAGES
)

# A sum of only the stages something has timed is a floor, so the word saying so sits on the number.
LATENCY_HEADLINE = f"at least {_stage_total:.2f}s"
LATENCY_CAPTION = (
    f"each stage&rsquo;s typical time, added together, over {DICTATIONS_TIMED} dictations, "
    f"without {len(NEVER_RUN_STAGES)} stages nothing has ever timed")

# One figure per measured stage, never an aggregate across the whole journey.
RELIABILITY = [
    ("100.0%", "Opening the microphone worked"),
    ("100.0%", "Recording worked"),
    ("97.6%", "Transcribing worked"),
    ("100.0%", "Checking the dictionary worked"),
    ("97.5%", "Tidying up worked"),
    ("100.0%", "Inserting worked"),
]

# Never a product name for the running engine; see §16.
ENGINE_ROWS = [
    ("Speech", "Downloaded speech model", "#34C759"),
    ("Built-in language model", "In use", "#34C759"),
    ("Built-in rules", "Ready if needed", "#34C759"),
]
CLEANUP_ROWS = [
    ("Filler words", "removed 3: um, hmm, aah", "#34C759"),
    ("Numbers", "Switched off", "var(--label-4)"),
]
PERMISSION_ROWS = [
    ("Microphone", "Granted", "#34C759"),
    ("Accessibility", "Granted", "#34C759"),
]
STORAGE_ROWS = [
    ("Speech model", "312 MB, on this Mac, every language", "#34C759"),
]


def fact_rows(rows):
    return "".join(
        f"""<div class="frow"><span class="dot" style="background:{colour}"></span>
                <span style="flex:1">{title}</span>
                <span class="d">{detail}</span></div>"""
        for title, detail, colour in rows
    )


def diag_section(title, rows):
    return f"""<p class="diaglabel">{title}</p>
        <div class="card">{fact_rows(rows)}</div>"""


# The verdict above the facts it is drawn from; a plain panel when nothing needs attention.
diag_verdict = """<div class="card diagverdict">
          <span class="dot"></span>
          <span style="flex:1">Everything Uttrflow needs is in place.</span>
        </div>"""

diag_reliability = "".join(
    f'<div class="stat"><div class="v">{value}</div><div class="k">{caption}</div></div>'
    for value, caption in RELIABILITY
)

# The right rail — engines, the last dictation's clean-up, permissions and storage — stacked once,
# reused by both the populated and the "no timings yet" pages since neither changes it.
diag_right_rail = (
    diag_section("Engines", ENGINE_ROWS)
    + diag_section("Clean-up steps, last dictation", CLEANUP_ROWS)
    + diag_section("Permissions", PERMISSION_ROWS)
    + diag_section("On this Mac", STORAGE_ROWS)
)
diag_right_rail_empty = (
    diag_section("Engines", ENGINE_ROWS)
    + diag_section(
        "Clean-up steps, last dictation",
        [("Clean-up steps", "Nothing dictated yet", "var(--label-4)")])
    + diag_section("Permissions", PERMISSION_ROWS)
    + diag_section("On this Mac", STORAGE_ROWS)
)
diag_footer = f"""<div class="row" style="margin-top: 10px; gap: 9px">
          <span class="muted" style="font-size: var(--t-footnote); flex: 1">{FOOTNOTE}</span>
          <button class="btn sm">Copy Diagnostics</button>
        </div>"""

# Two columns, left the timed journey, right what it is running on — the frame is fixed height
# and 700px is not enough for one long list of everything DiagnosticsPresentation reports.
diagnostics = f"""{diag_verdict}
        <div class="row" style="margin-top: 10px; gap: 14px; align-items: flex-start">
          <div style="flex: 3; min-width: 0">
            <p class="diaglabel" style="margin-top: 0">Time from letting go of the key to text on screen</p>
            <div class="card" style="padding: 10px 12px">
              <div class="row" style="justify-content: space-between; margin-bottom: 6px">
                <span style="font-size: var(--t-title3); font-weight: 600;
                  font-variant-numeric: tabular-nums">{LATENCY_HEADLINE}</span>
                <span class="muted" style="font-size: var(--t-footnote)">{LATENCY_CAPTION}</span>
              </div>
              <div class="bar-track">{lat_segments}</div>
            </div>
            <div class="card" style="margin-top: 8px">{lat_rows}{never_run_rows}</div>
            <div class="card diagstats" style="margin-top: 8px">{diag_reliability}</div>
          </div>
          <div style="flex: 2; min-width: 0">{diag_right_rail}</div>
        </div>
        {diag_footer}"""

# The state before anything has ever been timed: DiagnosticsPresenter.noTimingsYet.
diagnostics_empty = f"""{diag_verdict}
        <div class="row" style="margin-top: 10px; gap: 14px; align-items: flex-start">
          <div class="card" style="flex: 3; min-width: 0; padding: 0">
            <div class="empty" style="padding: 40px">
              <div class="ring">{icon(CHART, size=30, width=1.4)}</div>
              <h3>No timings yet</h3>
              <p>Dictate something and the times appear here. They stay on this Mac.</p>
            </div>
          </div>
          <div style="flex: 2; min-width: 0">{diag_right_rail_empty}</div>
        </div>
        {diag_footer}"""

written = []
for stem, active, tool_html, content in [
    ("Main-History", "History", tools(searchbox("Search history")), history),
    ("Main-Diagnostics", "Diagnostics", "", diagnostics),
    ("Main-Diagnostics-Empty", "Diagnostics", "", diagnostics_empty),
]:
    written += write_pair(
        stem,
        lambda dark, a=active, t=tool_html, c=content:
            app_window(a, t, c, dark, tails={"Corrections": "7"}, extra_css=MAIN_CSS),
    )
print(f"wrote {len(written)} main window artboards")
