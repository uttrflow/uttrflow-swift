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
    .hint { height: 34px; border-radius: 17px; display: flex; align-items: center; gap: 8px;
            padding: 0 15px; font-size: var(--t-body); }
    .badge { width: 30px; height: 30px; border-radius: 50%; flex: none; display: flex;
             align-items: center; justify-content: center; color: #FFFFFF; }
    .drow { display: flex; align-items: center; margin-bottom: 19px; }
    .kbd { display: inline-flex; align-items: center; justify-content: center; height: 20px;
           padding: 0 6px; border-radius: 5px; background: rgba(120,120,130,0.20);
           font-size: var(--t-footnote); font-weight: 600; }

    /* The resting grip carries no slab. Around a pill the glass reads as depth; around
       nine points of dots its hairline and its shadow read as a box nobody meant to
       draw, and the shipped build had two of them — the material's and the panel's. */
    .bare-grip { width: 9px; height: 34px; display: flex; flex-direction: column;
                 align-items: center; justify-content: center; gap: 3px;
                 filter: drop-shadow(0 0.5px 1.5px rgba(255,255,255,0.9)); }
    .dark-col .bare-grip { filter: drop-shadow(0 0.5px 1.5px rgba(0,0,0,0.55)); }
    .bare-grip i { width: 3px; height: 3px; border-radius: 50%;
                   background: rgba(0,0,0,0.6); }
    .dark-col .bare-grip i { background: rgba(255,255,255,0.6); }

    /* Listening and working are one size, because the panel must not change shape at
       the moment the key is released. */
    .compact { height: 32px; border-radius: 16px; display: flex; align-items: center;
               gap: 9px; padding: 0 12px 0 5px; }
    .weight { width: 22px; height: 22px; border-radius: 50%; flex: none; display: flex;
              align-items: center; justify-content: center; background: var(--accent); }
    .glass.dark .weight { background: var(--accent-dark); }
    /* Capsules, one per arrival, mirrored about the centre and walking toward the
       mark. Two teals the app already owns: past half height a bar takes the accent,
       below it the waveform teal at reduced weight — the hue cannot carry the threshold
       on its own, since the pair collapses to 1.05:1 on a dark desktop. */
    .meter { display: flex; align-items: center; gap: 1.8px; height: 18px; width: 56px;
             overflow: hidden; }
    .meter i { width: 2.2px; border-radius: 1.1px; flex: none; display: block;
               background: var(--accent-2-deep); opacity: 0.62; }
    .dark .meter i { background: var(--accent-2); }
    .meter i.loud { background: var(--accent); opacity: 1; }
    .dark .meter i.loud { background: var(--accent-dark); opacity: 1; }

    /* Working and inserting are one wait, so they are one row and one animation: three dots
       walking left to right, in the meter's own 56 points so the pill keeps its width. */
    .dots { display: flex; align-items: center; justify-content: center; gap: 6px;
            height: 18px; width: 56px; }
    .dots i { width: 5px; height: 5px; border-radius: 50%; background: var(--accent);
              display: block; }
    .dark .dots i { background: var(--accent-dark); }

    /* A success needs no words: the disc is the whole notice. */
    .disc { width: 26px; height: 26px; border-radius: 13px; display: flex;
            align-items: center; justify-content: center; }
    .struck { position: relative; width: 22px; height: 14px; display: flex;
              align-items: center; justify-content: center; gap: 2px; flex: none; }
    .struck i { width: 2px; border-radius: 2px; background: currentColor; opacity: 0.45;
                display: block; }
    .struck::after { content: ""; position: absolute; width: 20px; height: 1.5px;
                     background: currentColor; opacity: 0.62; transform: rotate(-34deg); }
    .clip { height: 28px; border-radius: 14px; display: flex; align-items: center;
            gap: 8px; padding: 0 9px; }
    /* The struck level and the sentence that says what happened, readable without the
       pointer over it — `DockView.quietNotice`, at the shared clipboard-notice height. */
    .quiet { display: flex; align-items: center; gap: 8px; min-height: 28px;
             border-radius: 14px; padding: 5px 10px; }
    .quiet .w { font-size: 11px; opacity: 0.72; max-width: 200px; line-height: 1.3; }
    .notice { height: 40px; border-radius: 20px; display: flex; align-items: center;
              gap: 12px; padding: 0 14px; width: 262px; }
    .notice .t { font-size: var(--t-body); font-weight: 500; }
    .notice .s { font-size: var(--t-footnote); opacity: 0.58; margin-top: 2px; }
"""


def struck():
    return (
        '<div class="struck"><i style="height:5px"></i><i style="height:9px"></i>'
        '<i style="height:6px"></i><i style="height:10px"></i><i style="height:4px"></i></div>'
    )


def meter_arrivals():
    heights = [12.0, 8.4, 5.3, 13.4, 10.4, 6.8, 14.6, 9.2, 4.4, 9.9, 5.7, 2.8, 2.2, 2.2]
    loud = {0, 1, 3, 4, 6, 7, 9}
    return "".join(
        f'<i class="loud" style="height:{h}px"></i>' if i in loud else f'<i style="height:{h}px"></i>'
        for i, h in enumerate(heights)
    )


def hover_meter():
    heights = [6, 11, 7]
    return '<div class="meter" style="height:11px">' + "".join(
        f'<i style="height:{h}px;background:currentColor;opacity:0.5"></i>' for h in heights
    ) + "</div>"


WEIGHT = (
    '<div class="weight"><svg width="9" height="10" viewBox="19 14 62 72" fill="none" '
    'stroke="#04100F" stroke-width="14" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M26 37 L26 55 A24 24 0 0 0 74 55 L74 21"/></svg></div>'
)

RESTING = '<div class="bare-grip"><i></i><i></i><i></i></div>'

HOVER = (
    '<div class="row" style="gap: 9px">'
    '<div class="glass{d} hint" style="height:30px;border-radius:15px">'
    'Dictate <span class="kbd">&#8997;Space</span></div>'
    '<div class="glass{d} orb" style="width:30px;height:30px">{hover_meter}</div></div>'
)

LISTENING = '<div class="glass{d} compact">{weight}<div class="meter">{arrivals}</div></div>'

WORKING = (
    '<div class="glass{d} compact">{weight}<div class="dots">'
    '<i style="opacity:1"></i><i style="opacity:0.62"></i><i style="opacity:0.34"></i></div></div>'
)

TICK = (
    '<svg width="15" height="15" viewBox="0 0 100 100" fill="none" stroke="#34C759" '
    'stroke-width="14" stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M20 54 L42 76 L82 26"/></svg>'
)

INSERTED = '<div class="glass{d} disc">{tick}</div>'

CLIPBOARD = '<div class="glass{d} clip"><span class="kbd" style="color:#FF8D28">&#8984;V</span></div>'

QUIET = '<div class="glass{d} quiet">{struck}<div class="w">Didn&rsquo;t catch that.</div></div>'

BLOCKED = (
    '<div class="glass{d} notice"><span class="badge" style="width:22px;height:22px;'
    'background:#FF8D28">{warn}</span><div style="flex:1"><div class="t">Microphone is off</div>'
    '<div class="s">System Settings &rarr; Privacy</div></div>'
    '<button class="btn sm" style="flex:none">Open</button></div>'
)

STATES = [
    ("Resting", "dots, and no box", RESTING),
    ("Pointed at", "reminds you of the key", HOVER),
    ("Listening", "capsules, one per arrival", LISTENING),
    ("Working", "and inserting &mdash; dots, left to right", WORKING),
    ("Inserted", "a tick, drawn on", INSERTED),
    ("Copied, not typed", "expands when pointed at", CLIPBOARD),
    ("Nothing heard", "the struck level, with the sentence at rest", QUIET),
    ("Blocked", "the only one still wide", BLOCKED),
]


def fill(tpl, dark):
    return tpl.format(
        d=" dark" if dark else "",
        weight=WEIGHT,
        arrivals=meter_arrivals(),
        hover_meter=hover_meter(),
        tick=TICK,
        struck=struck(),
        warn=icon(WARN, size=13, width=2),
    )


rows = ""
for name, desc, tpl in STATES:
    rows += f"""      <div class="drow">
        <div class="state-label"><div class="n">{name}</div><div class="d">{desc}</div></div>
        <div class="slot">{fill(tpl, False)}</div>
        <div style="width: 36px"></div>
        <div class="slot dark-col">{fill(tpl, True)}</div>
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
      <br><br>
      Listening and working are the same 32 points tall, so nothing moves at the moment you let go
      of the key &mdash; and working covers the wait for the app to take the words, because that is the
      same wait to the person waiting. The tick is a claim about the words, so it waits for them.
      Inserted is the one 26-point disc, because a success needs no
      words &mdash; when the text has landed you are already looking at it. Only the state with
      something to do about it is wide, and after a run of discs that width is the message.
    </div>
  </div>"""

with open("Dock-States.dc.html", "w") as handle:
    handle.write(
        page("Dock states", 900, 880, body, extra_css=DOCK_CSS, pad=34).replace(
            'class="stage"', 'class="stage dock"'
        )
    )
print("wrote Dock-States.dc.html")
