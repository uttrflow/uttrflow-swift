"""Every main-window destination the new sidebar leads to, light and dark,
full and empty.

Nothing on these screens is a number the app cannot already produce. Where a
tile would have needed a guess — "time saved", which needs an assumed typing
speed — it is left out and said so on the artboard, the same rule Diagnostics
already follows.
"""
from _gen_shell import *

APP_CSS = """
    .drow { display: flex; gap: 12px; align-items: flex-start; padding: 10px 13px; }
    .drow + .drow { border-top: 0.5px solid var(--separator); }
    .drow.hover { background: var(--hover-bg); }
    .drow .when { width: 52px; flex: none; font-size: var(--t-footnote); color: var(--label-2);
                  font-variant-numeric: tabular-nums; padding-top: 3px; }
    .drow .body { flex: 1; min-width: 0; }
    .drow .said { font-size: var(--t-body); line-height: 1.45; }
    .drow .meta { display: flex; align-items: center; gap: 6px; margin-top: 6px; height: 24px;
                  font-size: var(--t-footnote); color: var(--label-2); }
    /* Always laid out, so a row does not reflow the moment you point at it. */
    .acts { display: flex; gap: 5px; flex: none; margin-left: auto; visibility: hidden; }
    .drow.hover .acts { visibility: visible; }
    .mini { height: 6px; border-radius: 3px; background: var(--fill-2); overflow: hidden; }
    .mini > i { display: block; height: 100%; border-radius: 3px; background: var(--accent-light); }
    .field { border-radius: 6px; background: var(--control-bg);
             border: 0.5px solid var(--control-border); padding: 5px 8px;
             font-size: var(--t-callout); flex: 1; line-height: 1.5; }
    .field.focus { border-color: var(--accent); box-shadow: 0 0 0 3px rgba(18,128,119,0.26); }
    .grp { border-radius: var(--radius-card); border: 0.5px solid var(--separator);
           background: var(--card-bg); overflow: hidden;
           box-shadow: 0 1px 2px rgba(0,0,0,0.03); }
    .grp .r { display: flex; align-items: center; gap: 12px; padding: 8px 13px; min-height: 36px; }
    .grp .r + .r { border-top: 0.5px solid var(--separator); }
    .grp .r .desc { font-size: var(--t-subhead); color: var(--label-2); margin-top: 2px;
                    line-height: 1.35; }
    .grp .r .right { margin-left: auto; display: flex; align-items: center; gap: 8px; flex: none; }
    .grp-title { font-size: var(--t-subhead); font-weight: 600; color: var(--label-2);
                 margin: 13px 0 7px 3px; letter-spacing: 0.2px; }
    .sw { width: 36px; height: 21px; border-radius: 11px; background: var(--fill-2);
          position: relative; flex: none; }
    .sw.on { background: var(--accent-light); }
    .sw i { position: absolute; top: 2px; left: 2px; width: 17px; height: 17px;
            border-radius: 50%; background: #FFFFFF; box-shadow: 0 1px 2px rgba(0,0,0,0.22); }
    .sw.on i { left: 17px; }
    .seg { display: inline-flex; border-radius: 7px; background: var(--fill); padding: 2px; gap: 2px; }
    .seg span { padding: 0 11px; height: 21px; display: flex; align-items: center;
                border-radius: 5px; font-size: var(--t-callout); color: var(--label-2); }
    .seg span.on { background: var(--control-bg); color: var(--label); font-weight: 500;
                   box-shadow: 0 0.5px 1.5px rgba(0,0,0,0.16); }
    .chk { width: 15px; height: 15px; border-radius: 4px; background: var(--accent);
           display: flex; align-items: center; justify-content: center; color: #FFFFFF; flex: none; }
    .chk.off { background: transparent; border: 1px solid var(--label-3); }
    .avatar { width: 44px; height: 44px; border-radius: 50%; flex: none; display: flex;
              align-items: center; justify-content: center; font-size: var(--t-title3);
              font-weight: 600; color: var(--accent-text); background: var(--accent-wash);
              border: 1px solid var(--accent-tint); }
    .prov { display: inline-flex; align-items: center; gap: 6px; height: 22px; padding: 0 9px;
            border-radius: 6px; background: var(--fill); font-size: var(--t-callout); }
    .bars { display: flex; align-items: flex-end; gap: 10px; height: 86px; }
    .bars .b { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 6px;
               justify-content: flex-end; height: 100%; }
    .bars .b i { display: block; width: 100%; border-radius: 3px; background: var(--accent-light); }
    .bars .b.today i { background: var(--accent); }
    .bars .b.none i { background: var(--label-3); }
    .bars .b span { font-size: 9px; color: var(--label-3); font-variant-numeric: tabular-nums; }
    .legend { display: flex; gap: 13px; margin-top: 9px; font-size: var(--t-footnote);
              color: var(--label-2); align-items: center; }
    .swatch { width: 8px; height: 8px; border-radius: 3px; flex: none; }
    .track { height: 7px; border-radius: 4px; background: var(--fill-2); overflow: hidden; }
    .track > i { display: block; height: 100%; border-radius: 4px; background: var(--accent-light); }
"""

TAILS = {"Corrections": "7"}


def iconbtn(glyph, size=13, width=1.6):
    return f'<div class="iconbtn">{icon(glyph, size=size, width=width)}</div>'


ACTS = ('<div class="acts">' + iconbtn(COPY) + iconbtn(REPEAT) + iconbtn(FLAG)
        + iconbtn(MORE) + "</div>")


# =====================================================================
# Dictation — today's list, the surface that replaces the old Home.
# =====================================================================
DICTATIONS = [
    ("4:12 PM", "Slack", "#engineering",
     "Hey John, I&rsquo;ll probably be about 20 minutes late to the meeting &mdash; the "
     "deployment is still running.", "11s &middot; 21 words", "2 changes", False),
    ("3:48 PM", "Notes", "Standup",
     "Kal ke standup mein main deployment ke baare mein bataunga, abhi staging pe test "
     "chal raha hai.", "9s &middot; 16 words", "1 change", True),
    ("2:30 PM", "Code", "order_service.py",
     "Create a function that takes a user ID and returns their most recent order, or None "
     "if they have never ordered.", "14s &middot; 22 words", None, False),
    ("11:05 AM", "Mail", "Re: Q3 planning",
     "Thanks for putting this together &mdash; I have one concern about the timeline on "
     "the migration piece.", "8s &middot; 17 words", None, False),
    ("9:41 AM", "Slack", "Rahul Menon",
     "Bhai ye PR review kar dena aaj shaam tak, warna release slip ho jayega.",
     "6s &middot; 14 words", "1 change", False),
]


def dictation_rows():
    out = ""
    for when, app, doc, said, meta, changes, hovered in DICTATIONS:
        pill = (f'<span class="pill accent" style="margin-left:2px">{changes}</span>'
                if changes else "")
        out += f"""<div class="drow{' hover' if hovered else ''}">
            <span class="when">{when}</span>
            <div class="body">
              <div class="said">{said}</div>
              <div class="meta">{appchip(app)}<span>&middot;</span>
                <span style="white-space:nowrap">{doc}</span>
                <span>&middot;</span><span style="white-space:nowrap">{meta}</span>{pill}
                {ACTS}</div>
            </div>
          </div>"""
    return out


RAIL = f"""<div style="width: 186px; flex: none; display: flex; flex-direction: column; gap: 9px">
          <div class="card stat" style="padding: 10px 12px">
            <div class="v">1,240</div><div class="k">Words dictated</div>
            <div class="c">across 34 dictations</div>
          </div>
          <div class="card stat" style="padding: 10px 12px">
            <div class="v">131</div><div class="k">Words per minute</div>
            <div class="c">your usual pace is 126</div>
          </div>
          <div class="card stat" style="padding: 10px 12px">
            <div class="v">97.2%</div><div class="k">Accuracy</div>
            <div style="margin-top: 9px">
              <div class="row" style="gap: 7px; font-size: var(--t-footnote); color: var(--label-2)">
                <span style="width: 46px">Today</span>
                <div class="mini" style="flex:1"><i style="width: 97%"></i></div>
              </div>
              <div class="row" style="gap: 7px; margin-top: 5px; font-size: var(--t-footnote);
                   color: var(--label-2)">
                <span style="width: 46px">Baseline</span>
                <div class="mini" style="flex:1">
                  <i style="width: 95%; background: var(--label-3)"></i></div>
              </div>
            </div>
            <div class="c">Words you kept as written. Your baseline is 94.8%.</div>
          </div>
        </div>"""

dictation = f"""<div style="display: flex; gap: 15px; flex: 1; min-height: 0">
          <div style="flex: 1; min-width: 0; display: flex; flex-direction: column">
            <p class="daylabel">Today &middot; Sunday 23 August</p>
            <div class="card">{dictation_rows()}</div>
            <div class="foot">Point at a row for copy, insert again, flag and more.
              Today stays here; everything older moves to History.</div>
          </div>
          {RAIL}
        </div>"""

dictation_empty = f"""<div class="empty">
          <div class="ring">{icon(MIC, size=36, width=1.4)}</div>
          <h3>Nothing dictated today</h3>
          <p>Hold <span class="key">&#8997;</span>
            <span class="key" style="min-width: 50px">Space</span> anywhere and talk.
            You don&rsquo;t need this window open &mdash; whatever you say lands in the app
            you were already typing into.</p>
          <div class="chips">
            <div class="chip"><div class="cv">1,240</div><div class="ck">words yesterday</div></div>
            <div class="chip"><div class="cv">131</div><div class="ck">wpm yesterday</div></div>
            <div class="chip"><div class="cv">97.2%</div><div class="ck">accuracy yesterday</div></div>
          </div>
        </div>
        <div class="foot" style="text-align: center">Yesterday&rsquo;s figures, so the pane is
          never blank. Today&rsquo;s start counting from your first dictation.</div>"""


# =====================================================================
# Dictionary — the words a general model does not know.
# =====================================================================
COLS = [("Word", 116, "left"), ("Sounds like", 104, "left"), ("Where from", 106, "left"),
        ("Added", 60, "left"), ("Used", 38, "right"), ("Undone", 46, "right"),
        ("", 56, "right")]

WORDS = [
    ("Uttrflow", "utter-flow", "Added by you", "12 Aug", "34", "0", False, False),
    ("Naveen Bhatt", "&mdash;", "Learned", "2 Aug", "118", "1", False, False),
    ("pgvector", "pee-gee vector", "Seen on screen", "19 Aug", "9", "0", False, True),
    ("asyncpg", "a-sync-p-g", "Seen on screen", "20 Aug", "6", "0", False, False),
    ("Valkey", "val-key", "Learned", "14 Aug", "22", "2", False, False),
    ("shirorekha", "shiro-rekha", "Added by you", "12 Aug", "3", "0", False, False),
    ("Hinglish", "&mdash;", "Learned", "7 Aug", "41", "0", False, False),
    ("Kestrel", "kes-trel", "Learned", "9 Aug", "15", "7", True, False),
]


def dict_header():
    cells = "".join(
        f'<span class="{"num" if align == "right" else ""}" '
        f'style="width:{w}px; flex:none">{label}</span>'
        for label, w, align in COLS)
    return f'<div class="th">{cells}</div>'


def dict_rows():
    out = ""
    for word, sounds, source, added, used, undone, retired, hovered in WORDS:
        classes = "tr" + (" hover" if hovered else "")
        # A retired row is dimmed, but the control that un-retires it is not.
        dim = "opacity:0.45; " if retired else ""
        tail = ('<button class="btn sm" style="height:20px; padding:0 8px">Restore</button>'
                if retired else (iconbtn(MORE, size=12) if hovered else ""))
        badge = ('<span class="pill warn" style="margin-left:6px">Retired</span>'
                 if retired else "")
        out += f"""<div class="{classes}">
            <span style="{dim}width:{COLS[0][1]}px; flex:none; font-weight:500;
              color:var(--label); display:flex; align-items:center">{word}{badge}</span>
            <span style="{dim}width:{COLS[1][1]}px; flex:none; color:var(--label-2)">{sounds}</span>
            <span style="{dim}width:{COLS[2][1]}px; flex:none; color:var(--label-2)">{source}</span>
            <span style="{dim}width:{COLS[3][1]}px; flex:none; color:var(--label-2)">{added}</span>
            <span class="num" style="{dim}width:{COLS[4][1]}px; flex:none">{used}</span>
            <span class="num" style="{dim}width:{COLS[5][1]}px; flex:none;
              color:{'var(--red)' if int(undone) > 2 else 'var(--label-2)'}">{undone}</span>
            <span style="width:{COLS[6][1]}px; flex:none; display:flex;
              justify-content:flex-end">{tail}</span>
          </div>"""
    return out


dictionary = f"""<p class="daylabel">24 words Uttrflow knows and a general model does not</p>
        <div class="card" style="overflow: hidden">{dict_header()}{dict_rows()}</div>
        <div class="foot">
          <b style="font-weight:600">Learned</b> means you corrected it and Uttrflow kept the
          correction. <b style="font-weight:600">Seen on screen</b> means it was in front of you
          while you spoke. <b style="font-weight:600">Added by you</b> means you typed it in here.<br>
          Kestrel retired itself: you undid it 7 times out of 15, so Uttrflow stopped applying it.
          Restore to try again. Every word here stays on this Mac.
        </div>"""

dictionary_empty = f"""<div class="empty">
          <div class="ring">{icon(BOOK, size=34, width=1.4)}</div>
          <h3>No words of your own yet</h3>
          <p>Uttrflow learns the names, products and jargon a general model has never heard.
            Correct a word once and it lands here; so do terms it can see on your screen
            while you speak.</p>
          <div style="margin-top: 20px">
            <button class="btn primary">{icon(PLUS, size=12, width=2)}
              <span>Add a Word</span></button>
          </div>
        </div>
        <div class="foot" style="text-align: center">Nothing is pre-loaded. An empty
          dictionary means Uttrflow has not yet changed a single word of yours.</div>"""


# =====================================================================
# Corrections — what was changed, and why.
# =====================================================================
CHANGES = [
    ("utter flow", "Uttrflow", "Your dictionary", "4:12 PM", "Slack", None),
    ("um, I think we should", "I think we should", "Filler removed", "4:12 PM", "Slack", None),
    ("a sink p g", "asyncpg", "Seen on screen", "2:30 PM", "Code", None),
    ("mein", "main", "Hinglish spelling", "3:48 PM", "Notes", None),
    ("naveen bhat", "Naveen Bhatt", "Your dictionary", "11:05 AM", "Mail", None),
    ("postgress", "Postgres", "Common misspelling", "2:30 PM", "Code", None),
    ("your late", "you&rsquo;re late", "Grammar", "9:41 AM", "Slack", "undone"),
]


def change_rows():
    out = ""
    for heard, wrote, why, when, app, state in CHANGES:
        if state == "undone":
            action = '<span class="pill good">Undone</span>'
            wrote_html = (f'<span style="color: var(--label-3); text-decoration: line-through">'
                          f'{wrote}</span>')
        else:
            action = ('<button class="btn sm" style="height:20px; padding:0 9px">'
                      f'{icon(UNDO, size=11, width=1.8)}<span>Undo</span></button>')
            wrote_html = f'<span style="font-weight: 600">{wrote}</span>'
        out += f"""<div class="tr">
            <span style="flex:1; min-width:0; display:flex; align-items:center; gap:7px">
              <span style="color: var(--label-2)">&ldquo;{heard}&rdquo;</span>
              <span style="color: var(--label-3)">&rarr;</span>
              {wrote_html}</span>
            <span style="width:126px; flex:none"><span class="pill">{why}</span></span>
            <span style="width:112px; flex:none; color: var(--label-2); display:flex;
              align-items:center; gap:5px; white-space:nowrap">{when} &middot;
              {appchip(app)}</span>
            <span style="width:74px; flex:none; display:flex; justify-content:flex-end">
              {action}</span>
          </div>"""
    return out


corrections = f"""<div class="callout" style="margin-bottom: 12px">
          <span style="flex:none; color: var(--accent-text); margin-top:1px">
            {icon(SWAP, size=14, width=1.7)}</span>
          <span>Every word Uttrflow changed today, and why. A product that quietly rewrites
            what you said owes you this page &mdash; nothing here happened without a reason,
            and nothing here is permanent.</span>
        </div>
        <p class="daylabel">Today &middot; 7 changes across 34 dictations</p>
        <div class="card" style="overflow: hidden">{change_rows()}</div>
        <div class="foot">Undo teaches Uttrflow. Undo the same change three times and it stops
          making it &mdash; the word retires itself in your Dictionary.</div>"""

corrections_empty = f"""<div class="empty">
          <div class="ring">{icon(SWAP, size=34, width=1.4)}</div>
          <h3>Uttrflow changed nothing you said today</h3>
          <p>It only changes a word when it has a reason it can name: a word in your
            dictionary, a term it could see on your screen, a filler word, or punctuation.
            When it does, the change is listed here with what it heard, what it wrote,
            and an undo.</p>
          <div class="chips">
            <div class="chip"><div class="cv">34</div><div class="ck">dictations today</div></div>
            <div class="chip"><div class="cv">0</div><div class="ck">words changed</div></div>
          </div>
        </div>
        <div class="foot" style="text-align: center">An empty page here is the good outcome,
          not a missing feature.</div>"""


# =====================================================================
# Insights — only what the app already measures.
# =====================================================================
DAYS = [310, 640, 0, 520, 880, 960, 210, 705, 890, 1120, 0, 795, 1150, 1240]
DATES = [str(d) for d in range(10, 24)]
WPM = [118, 124, 121, 129, 133, 126, 130, 128, 135, 131, 134, 131]
PEAK = max(DAYS)


def day_bars():
    out = ""
    for i, (v, label) in enumerate(zip(DAYS, DATES)):
        cls = "b today" if i == len(DAYS) - 1 else ("b none" if v == 0 else "b")
        height = 4 if v == 0 else max(6, round(v / PEAK * 70))
        out += (f'<div class="{cls}"><i style="height:{height}px"></i>'
                f'<span>{label}</span></div>')
    return out


def sparkline(values, w=150, h=30):
    lo, hi = min(values), max(values)
    span = (hi - lo) or 1
    step = w / (len(values) - 1)
    pts = " ".join(f"{i * step:.1f},{h - 2 - (v - lo) / span * (h - 5):.1f}"
                   for i, v in enumerate(values))
    return (f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none">'
            f'<polyline points="{pts}" stroke="var(--accent-light)" stroke-width="1.6" '
            'stroke-linecap="round" stroke-linejoin="round"/></svg>')


LANGS = [("English", 68, "var(--accent)"), ("Hinglish", 24, "var(--accent-2)"),
         ("Hindi", 8, "var(--accent-tint)")]
PLACES = [("Slack", 41), ("Code", 26), ("Mail", 18), ("Notes", 15)]

lang_bar = "".join(f'<div style="width:{p}%; background:{c}"></div>' for _, p, c in LANGS)
lang_legend = "".join(
    f'<span class="row" style="gap:5px"><span class="swatch" style="background:{c}"></span>'
    f'{n} {p}%</span>' for n, p, c in LANGS)
place_rows = "".join(
    f"""<div class="row" style="gap:8px; margin-top:{7 if i else 9}px;
         font-size: var(--t-footnote)">
      <span style="width:78px; display:flex; align-items:center; gap:5px">{appchip(n)}</span>
      <div class="mini" style="flex:1"><i style="width:{p * 2.4:.0f}%"></i></div>
      <span class="num" style="width:26px; color: var(--label-2)">{p}%</span>
    </div>""" for i, (n, p) in enumerate(PLACES))

insights = f"""<div class="card" style="padding: 12px 14px">
          <div class="row" style="justify-content: space-between; align-items: baseline">
            <span style="font-size: var(--t-title3); font-weight: 600">Words dictated</span>
            <span class="muted" style="font-size: var(--t-footnote)">
              {sum(DAYS):,} words &middot; 10&ndash;23 August</span>
          </div>
          <div class="bars" style="margin-top: 10px">{day_bars()}</div>
        </div>
        <div class="row" style="gap: 12px; margin-top: 12px; align-items: stretch">
          <div class="card stat" style="flex: 1; padding: 11px 13px">
            <div class="row" style="justify-content: space-between; align-items: flex-end">
              <div><div class="v">131</div><div class="k">Words per minute</div></div>
              {sparkline(WPM)}
            </div>
            <div class="c">Your 14-day average is 128. Days you did not dictate are skipped.</div>
          </div>
          <div class="card stat" style="width: 214px; flex: none; padding: 11px 13px">
            <div class="v">97.2%</div><div class="k">Accuracy</div>
            <div class="row" style="gap: 7px; margin-top: 9px; font-size: var(--t-footnote);
                 color: var(--label-2)">
              <span style="width: 46px">Now</span>
              <div class="mini" style="flex:1"><i style="width: 97%"></i></div>
            </div>
            <div class="row" style="gap: 7px; margin-top: 5px; font-size: var(--t-footnote);
                 color: var(--label-2)">
              <span style="width: 46px">Baseline</span>
              <div class="mini" style="flex:1">
                <i style="width: 95%; background: var(--label-3)"></i></div>
            </div>
            <div class="c">Words kept as written, against your first week: 94.8%.</div>
          </div>
        </div>
        <div class="row" style="gap: 12px; margin-top: 12px; align-items: stretch">
          <div class="card" style="flex: 1; padding: 11px 13px">
            <div style="font-size: var(--t-body); font-weight: 600">Languages you spoke</div>
            <div class="bar-mix" style="display:flex; height: 22px; border-radius: 6px;
                 overflow: hidden; margin-top: 11px">{lang_bar}</div>
            <div class="legend">{lang_legend}</div>
          </div>
          <div class="card" style="width: 214px; flex: none; padding: 11px 13px">
            <div style="font-size: var(--t-body); font-weight: 600">Where you dictate</div>
            {place_rows}
          </div>
        </div>
        <div class="foot">Measured on this Mac over the last 14 days. Never sent anywhere.<br>
          There is no &ldquo;time saved&rdquo; tile: it would need a guess at how fast you type,
          and Uttrflow has never watched you type.</div>"""

insights_empty = f"""<div class="empty">
          <div class="ring">{icon(CHART, size=34, width=1.4)}</div>
          <h3>Not enough to chart yet</h3>
          <p>Insights compare this week against your own baseline, so they wait until there
            are seven days to compare. Uttrflow has two.</p>
          <div style="width: 280px; margin-top: 20px">
            <div class="track"><i style="width: 28.5%"></i></div>
            <div class="row" style="justify-content: space-between; margin-top: 8px;
                 font-size: var(--t-footnote); color: var(--label-2)">
              <span>2 of 7 days</span><span>Charts appear on Tuesday</span>
            </div>
          </div>
          <div class="chips">
            <div class="chip"><div class="cv">68</div><div class="ck">dictations so far</div></div>
            <div class="chip"><div class="cv">2,410</div><div class="ck">words so far</div></div>
          </div>
        </div>
        <div class="foot" style="text-align: center">The two numbers Uttrflow can honestly
          give on day two are given. The rest waits rather than guessing.</div>"""


# =====================================================================
# Snippets — a phrase you say, a block of text you get.
# =====================================================================
SNIPS = [
    ("my address", "Flat 402, Example Residences, Sample Road, Bengaluru 560001", "12", "Tuesday"),
    ("standup update", "Yesterday: &hellip; &nbsp;Today: &hellip; &nbsp;Blockers: &hellip;",
     "31", "Today"),
    ("meeting link", "https://meet.google.com/qzt-hnrv-dka", "48", "Today"),
    ("sign off", "Thanks, Naveen", "64", "Today"),
]

snip_rows = "".join(f"""<div class="tr">
            <span style="width:128px; flex:none"><span class="pill accent">&ldquo;{t}&rdquo;</span></span>
            <span style="flex:1; min-width:0; color: var(--label-2); overflow:hidden;
              text-overflow:ellipsis; white-space:nowrap">{x}</span>
            <span class="num" style="width:36px; flex:none">{u}</span>
            <span style="width:66px; flex:none; color: var(--label-2)">{l}</span>
          </div>""" for t, x, u, l in SNIPS)

snip_editor = f"""<div style="padding: 11px 13px; background: var(--hover-bg);
             border-top: 0.5px solid var(--separator)">
            <div class="row" style="gap: 10px">
              <span style="width: 88px; flex:none; font-size: var(--t-footnote);
                color: var(--label-2)">When I say</span>
              <div class="field focus" style="max-width: 200px">invoice terms</div>
              <span class="pill" style="margin-left: 4px">Editing</span>
            </div>
            <div class="row" style="gap: 10px; align-items: flex-start; margin-top: 9px">
              <span style="width: 88px; flex:none; font-size: var(--t-footnote);
                color: var(--label-2); padding-top: 6px">Type this</span>
              <div class="field" style="height: 52px">Payment due within 15 days of the
                invoice date. Late payments accrue 1.5% per month.</div>
            </div>
            <div class="row" style="gap: 8px; justify-content: flex-end; margin-top: 10px">
              <button class="btn sm">Cancel</button>
              <button class="btn sm primary">Save</button>
            </div>
          </div>"""

snippets = f"""<p class="daylabel">5 snippets</p>
        <div class="card" style="overflow: hidden">
          <div class="th"><span style="width:128px; flex:none">Trigger</span>
            <span style="flex:1">Types</span>
            <span class="num" style="width:36px; flex:none">Used</span>
            <span style="width:66px; flex:none">Last used</span></div>
          {snip_rows}{snip_editor}
        </div>
        <div class="foot">Say the trigger anywhere in a sentence and Uttrflow swaps in the text.
          Triggers are matched on what you said, so &ldquo;my address&rdquo; works whether you
          pause around it or not.</div>"""

snippets_empty = f"""<div class="empty">
          <div class="ring">{icon(SNIPPET, size=32, width=1.4)}</div>
          <h3>No snippets yet</h3>
          <p>A snippet turns something you say into a block of text you would rather not
            say out loud every time &mdash; an address, a standup format, a sign-off.</p>
          <div class="card" style="margin-top: 18px; padding: 10px 13px; width: 400px;
               text-align: left">
            <div style="font-size: var(--t-footnote); color: var(--label-3); font-weight: 600;
                 letter-spacing: 0.3px; text-transform: uppercase">For example</div>
            <div class="row" style="gap: 8px; margin-top: 8px; font-size: var(--t-callout)">
              <span class="pill accent">&ldquo;my address&rdquo;</span>
              <span style="color: var(--label-3)">&rarr;</span>
              <span style="color: var(--label-2)">Flat 402, Example Residences, Bengaluru</span>
            </div>
          </div>
          <div style="margin-top: 18px">
            <button class="btn primary">{icon(PLUS, size=12, width=2)}
              <span>New Snippet</span></button>
          </div>
        </div>"""


# =====================================================================
# Style — how much tidying, and which languages. Settings idiom.
# =====================================================================
def sw(on):
    return f'<div class="sw{" on" if on else ""}"><i></i></div>'


def seg(options, active):
    return ('<div class="seg">'
            + "".join(f'<span class="{"on" if o == active else ""}">{o}</span>'
                      for o in options) + "</div>")


def srow(label, right, desc=None):
    d = f'<div class="desc">{desc}</div>' if desc else ""
    return (f'<div class="r"><div><div>{label}</div>{d}</div>'
            f'<div class="right">{right}</div></div>')


def lang_row(name, native, checked):
    mark = (f'<div class="chk">{icon(CHECK, size=10, width=3)}</div>' if checked
            else '<div class="chk off"></div>')
    sub = f'<div class="desc">{native}</div>' if native else ""
    return (f'<div class="r"><div class="row" style="gap:10px">{mark}'
            f'<div><div>{name}</div>{sub}</div></div></div>')


EXAMPLE = """<div class="card" style="padding: 10px 13px; margin-top: 10px">
          <div style="font-size: var(--t-footnote); color: var(--label-3); font-weight: 600;
               letter-spacing: 0.3px; text-transform: uppercase">The same sentence, both ways</div>
          <div class="row" style="gap: 10px; margin-top: 8px; font-size: var(--t-callout);
               align-items: flex-start">
            <span style="width: 74px; flex:none; color: var(--label-2)">You said</span>
            <span style="color: var(--label-2)">um so i think we should uh ship it on friday</span>
          </div>
          <div class="row" style="gap: 10px; margin-top: 6px; font-size: var(--t-callout);
               align-items: flex-start">
            <span style="width: 74px; flex:none; color: var(--label-2)">Light</span>
            <span>Um, so I think we should, uh, ship it on Friday.</span>
          </div>
          <div class="row" style="gap: 10px; margin-top: 6px; font-size: var(--t-callout);
               align-items: flex-start">
            <span style="width: 74px; flex:none; color: var(--label-2)">Standard</span>
            <span>I think we should ship it on Friday.
              <span class="pill accent" style="margin-left: 5px">Current</span></span>
          </div>
        </div>"""

style = f"""<p class="grp-title" style="margin-top: 0">Tidying up</p>
        <div class="grp">
          {srow("How much Uttrflow tidies", seg(["Light", "Standard"], "Standard"),
                "Light fixes punctuation and capitalisation only. Standard also drops filler "
                "words and repairs grammar.")}
          {srow("Never change technical terms", sw(True),
                "Code, package names and anything in your Dictionary come through exactly as "
                "you said them.")}
        </div>
        {EXAMPLE}
        <p class="grp-title">Languages</p>
        <div class="grp">
          {srow("Detect the language as I speak", sw(True),
                "Recommended. Uttrflow works out which language you are in, including when you "
                "switch mid-sentence.")}
          {lang_row("English", "", True)}
          {lang_row("Hindi", "&#2361;&#2367;&#2344;&#2381;&#2342;&#2368; &mdash; typed in Devanagari or romanised, as you said it", True)}
          <div class="r"><div style="color: var(--accent-text)">Add Language&hellip;</div></div>
        </div>
        <div class="callout" style="margin-top: 12px">
          <span style="flex:none; color: var(--accent-text); margin-top:1px">
            {icon(GLOBE, size=14, width=1.7)}</span>
          <span>Tidying is strongest in English. Hindi and Hinglish get punctuation and
            spacing, not rewriting &mdash; anything Uttrflow does change shows up in
            Corrections.</span>
        </div>"""


# =====================================================================
# Account — who is signed in, and what that does and does not mean.
# =====================================================================
account = f"""<div class="card" style="padding: 14px 15px">
          <div class="row" style="gap: 13px">
            <div class="avatar">NB</div>
            <div style="flex: 1; min-width: 0">
              <div style="font-size: var(--t-title3); font-weight: 600">Naveen Bhatt</div>
              <div class="muted" style="font-size: var(--t-callout); margin-top: 2px">
                nadia.d@example.com</div>
            </div>
            <div class="prov">{google_mark(14)}<span>Google</span></div>
          </div>
        </div>
        <div class="grp" style="margin-top: 12px">
          {srow("Plan", '<span style="font-size: var(--t-callout)">Free</span>',
                "Unlimited dictation on this Mac. Nothing to pay, nothing metered.")}
          {srow("Signed in since", '<span style="font-size: var(--t-callout)">12 August</span>')}
          {srow("Sign out",
                '<button class="btn sm destructive">Sign Out</button>',
                "Uttrflow stops until you sign in again. It needs the network for that one step.")}
        </div>
        <div class="callout" style="margin-top: 12px">
          <span style="flex:none; color: var(--green); margin-top:1px">
            {icon(LOCK, size=15, width=1.7)}</span>
          <span>The account is an identity and nothing more. Your recordings, transcripts,
            Dictionary, Corrections and Snippets are files on this Mac &mdash; signing out
            leaves every one of them exactly where it is.</span>
        </div>
        <div class="foot">Uttrflow reaches the network to sign you in, and for nothing else.
          Turn Wi-Fi off afterwards and dictation carries on working.</div>"""


# =====================================================================
SCREENS = [
    ("Main-Dictation", "Dictation",
     tools(searchbox("Search today")), dictation, RECENT, TAILS),
    ("Main-Dictation-Empty", "Dictation",
     tools(searchbox("Search today")), dictation_empty, RECENT_NONE, None),
    ("Main-Dictionary", "Dictionary",
     tools(searchbox("Search words"), addbtn("Add Word")), dictionary, RECENT, TAILS),
    ("Main-Dictionary-Empty", "Dictionary",
     tools(searchbox("Search words"), addbtn("Add Word")), dictionary_empty, RECENT, None),
    ("Main-Corrections", "Corrections",
     tools(pop("All changes"), searchbox("Search")), corrections, RECENT, TAILS),
    ("Main-Corrections-Empty", "Corrections",
     tools(pop("All changes"), searchbox("Search")), corrections_empty, RECENT, None),
    ("Main-Insights", "Insights", tools(pop("Last 14 days")), insights, RECENT, TAILS),
    ("Main-Insights-Empty", "Insights", tools(pop("Since 21 August")), insights_empty,
     RECENT_NONE, None),
    ("Main-Snippets", "Snippets",
     tools(searchbox("Search snippets"), addbtn("New Snippet")), snippets, RECENT, TAILS),
    ("Main-Snippets-Empty", "Snippets",
     tools(searchbox("Search snippets"), addbtn("New Snippet")), snippets_empty,
     RECENT_NEVER, None),
    ("Main-Style", "Style", "", style, RECENT, TAILS),
    ("Main-Account", "Account", "", account, RECENT, TAILS),
]

written = []
for stem, active, tool_html, content, recent, tails in SCREENS:
    written += write_pair(
        stem,
        lambda dark, a=active, t=tool_html, c=content, r=recent, x=tails:
            app_window(a, t, c, dark, recent=r, tails=x, extra_css=APP_CSS),
    )
print(f"wrote {len(written)} app-window artboards")
