"""First-run onboarding: seven pages, every state each of them can be in.

The wording here is not invented. Every title, subtitle, body and note below is
the string `UttrflowUX/OnboardingPresenter.swift` actually returns for that state,
and every button is the one it actually offers, in the order it offers it. The
presenter is the only place the approved designs are written down, so an artboard
that paraphrased it would be a second opinion nobody would notice going stale —
which is precisely what happened to the row of dots.

Two pages are worth reading the source for before touching the copy:

  * The download (step 5) is the only page that can fail while the user watches,
    so it is drawn twice — mid-download and stopped.
  * The microphone check (step 6) is called a *check* and never training. The
    recogniser is a fixed model: no on-device fine-tuning, no speaker embedding,
    so nothing measured here changes how anybody is heard. `OnboardingMicrophone
    CheckTests` fails the build on "train", "learn your voice", "adapt",
    "personalis" and "your accent" appearing in that page's words, and the same
    rule is worth holding the drawing to. Note also what the finished page does
    *not* show: the noise floor is kept, not displayed — a level in dBFS means
    nothing to anybody, so the page says what it changed instead.

Sign-in is step 1 and is drawn by `_gen_signin.py`; it takes its dot from the
shared `dots()` helper so the two files cannot disagree about how long this is.
"""
from _gen_shell import *

W, H = 620, 470
STAGE_W, STAGE_H = 700, 550

# ---- glyphs this row needs and the shared set does not carry -------------
# Named for the SF Symbol the presenter asks for, so the two can be compared.
WAVEFORM = '<path d="M3.4 10.6v2.8M7.7 7v10M12 3.8v16.4M16.3 8.4v7.2M20.6 10.9v2.2"/>'
EAR = ('<path d="M6.6 10.4a5.4 5.4 0 1 1 10.8 0c0 2.6-1.7 3.8-2.8 4.9-.9.9-1.3 1.7-1.5 2.7'
       '-.3 1.6-1.3 2.7-2.9 2.7a2.6 2.6 0 0 1-2.6-2.6"/>'
       '<path d="M9.6 10.6a2.4 2.4 0 0 1 4.8 0c0 1.4-.8 2-1.7 2.8"/>')
QUOTE = '<path d="M4.6 5.2v13.6"/><path d="M9.2 7.6h10.2M9.2 12h10.2M9.2 16.4h6.4"/>'
MIC_SLASH = ('<path d="M9 6.5a3 3 0 0 1 6 0v3.1"/>'
             '<path d="M15 13.3a3 3 0 0 1-6-.3V9.4"/>'
             '<path d="M5.5 10.5v1a6.5 6.5 0 0 0 9.8 5.6"/>'
             '<path d="M18.5 10.5v1c0 .8-.14 1.6-.41 2.3"/>'
             '<path d="M12 18v3"/><path d="M3.7 3.7 20.3 20.3"/>')

ONB_CSS = """
    .onb-top { height: 40px; display: flex; align-items: center; padding: 0 14px; }
    .onb-body { flex: 1; display: flex; flex-direction: column; align-items: center;
                justify-content: center; text-align: center; padding: 0 64px; }
    .onb-foot { display: flex; align-items: center; justify-content: space-between;
                padding: 18px 24px 22px; }
    .glyph {
      width: 76px; height: 76px; border-radius: 18px;
      display: flex; align-items: center; justify-content: center;
      background: linear-gradient(180deg, #F4F4F7 0%, #E7E7EC 100%);
      border: 0.5px solid rgba(0,0,0,0.10);
      box-shadow: 0 1px 2px rgba(0,0,0,0.06);
      color: var(--label-2);
    }
    .glyph.brand { background: linear-gradient(180deg, #F5FAF9 0%, var(--accent-wash) 100%);
                   border-color: rgba(18,128,119,0.16);
                   box-shadow: 0 6px 20px rgba(18,128,119,0.16); }
    .glyph.good { background: linear-gradient(180deg, #4BD46B 0%, #2FB84E 100%);
                  border-color: transparent; color: #FFFFFF;
                  box-shadow: 0 6px 18px rgba(52,199,89,0.30); }
    /* Dark re-declares the tile rather than filtering it: the neutral one is a
       raised surface and has to sit above #1E1E1E, and the brand one is a tint
       of the accent, which on dark is a wash rather than a near-white. */
    .theme-dark .glyph { background: linear-gradient(180deg, #3A3A3D 0%, #2C2C2E 100%);
                         border-color: rgba(255,255,255,0.10);
                         box-shadow: 0 1px 2px rgba(0,0,0,0.45); }
    .theme-dark .glyph.brand {
      background: linear-gradient(180deg, rgba(18,128,119,0.34) 0%, rgba(18,128,119,0.16) 100%);
      border-color: rgba(41,192,180,0.30);
      box-shadow: 0 6px 20px rgba(18,128,119,0.34); }
    .theme-dark .glyph.good { background: linear-gradient(180deg, #4BD46B 0%, #2FB84E 100%);
                              border-color: transparent; color: #FFFFFF;
                              box-shadow: 0 6px 18px rgba(52,199,89,0.34); }
    .h-title { font-size: var(--t-large-title); font-weight: 700; letter-spacing: -0.3px;
               margin: 22px 0 0; }
    .h-sub { font-size: var(--t-title3); font-weight: 400; color: var(--label-2);
             margin: 8px 0 0; max-width: 420px; text-wrap: pretty; }
    .h-body { font-size: var(--t-body); color: var(--label-2); margin: 16px 0 0;
              line-height: 1.45; max-width: 400px; text-wrap: pretty; }
    .track { width: 100%; height: 6px; border-radius: 3px; background: var(--fill-2); overflow: hidden; }
    .track > i { display: block; height: 100%; border-radius: 3px; background: var(--accent-light); }
    .note { display: flex; gap: 8px; align-items: flex-start; margin-top: 22px;
            padding: 10px 12px; border-radius: var(--radius-card); background: var(--fill);
            font-size: var(--t-callout); color: var(--label-2); text-align: left; max-width: 420px; }
    /* The passage, sized to be read off the screen from a normal sitting distance
       rather than leaned into. */
    .passage { margin-top: 18px; max-width: 430px; padding: 14px 18px;
               border-radius: var(--radius-card); background: var(--fill);
               font-size: var(--t-title3); line-height: 1.5; color: var(--label);
               text-wrap: pretty; }
    /* The input level, drawn because both listening pages are holding a live
       microphone and a page that showed nothing would look frozen.
       The bars sit inside a visible track on purpose: a quiet room is a row of
       very short bars, and without something to be short *against* it reads as
       a line of full stops rather than as a measurement. */
    .meter { display: flex; align-items: center; justify-content: center; gap: 4px;
             width: 264px; height: 36px; margin: 20px auto 0; border-radius: 9px;
             background: var(--fill); }
    .meter i { display: block; width: 4px; border-radius: 2px; background: var(--accent-light); }
    .meter.quiet i { background: var(--label-3); }
"""


def meter(levels, quiet=False):
    """A row of input-level bars, each a height in px."""
    bars = "".join(f'<i style="height: {h}px"></i>' for h in levels)
    return f'<div class="meter{" quiet" if quiet else ""}">{bars}</div>'


ROOM = [3, 4, 3, 5, 4, 3, 4, 6, 4, 3, 5, 4, 3, 4, 3, 5, 4, 3, 4, 3]
SPEAKING = [6, 11, 19, 26, 17, 9, 14, 24, 30, 21, 12, 8, 15, 23, 28, 18, 10, 7, 12, 6]


def onboarding(step, glyph_class, glyph_inner, title, sub, body_html, actions_html):
    """One onboarding page, as a builder `write_pair` can call for each appearance."""

    def build(dark):
        html = page(
            title,
            STAGE_W,
            STAGE_H,
            f"""  <div class="win" style="width: {W}px; height: {H}px">
    <div class="onb-top">{lights()}</div>
    <div class="onb-body">
        <div class="glyph {glyph_class}">{glyph_inner}</div>
      <h1 class="h-title">{title}</h1>
      <p class="h-sub">{sub}</p>
      {body_html}
    </div>
    <div class="onb-foot">
      {dots(step)}
      <div class="row" style="gap: 10px">{actions_html}</div>
    </div>
  </div>""",
            extra_css=SHELL_CSS + DOTS_CSS + ONB_CSS,
        )
        return html.replace('class="stage"', 'class="stage night theme-dark"') if dark else html

    return build


def note(glyph, text):
    return f"""<div class="note">
         <span style="color: var(--label-3); flex: none; margin-top: 1px">
           {icon(glyph, size=14, width=1.7)}</span>
         <span>{text}</span>
       </div>"""


# The two notes the presenter repeats across every form of a page, held once here
# for the same reason it holds them once there.
STAYS_ON_THIS_MAC = note(
    LOCK,
    """Once this finishes, dictation runs on this Mac &mdash; it keeps working
         with Wi-Fi off, on a plane, anywhere.""")
NOTHING_IS_KEPT = note(
    LOCK,
    """Nothing you say here is saved. What is kept is three numbers: how quiet
         your room is, how much of the passage came back, and which languages
         you spoke.""")

pages = {}

# ---- 1. Welcome ----------------------------------------------------------
# First, so the product says what it is before it asks who you are. Signing in is
# required to dictate, and demanding an account on the very first screen would be
# asking the price before naming the thing.
pages["Onboarding-Welcome"] = onboarding(
    1, "brand", logo(52),
    "Speak naturally.",
    "Get the words you actually meant.",
    """<p class="h-body">Hold one key, say what you mean, and Uttrflow writes it into
         whatever app you&rsquo;re in &mdash; punctuated, tidied, and without the
         &ldquo;um&rdquo;s.</p>""",
    '<button class="btn primary">Continue</button>',
)

# ---- 3. Microphone -------------------------------------------------------
pages["Onboarding-Microphone"] = onboarding(
    3, "", icon(MIC, size=38, width=1.6),
    "Let Uttrflow hear you",
    "It needs your microphone to do anything at all.",
    """<p class="h-body">Audio is processed on this Mac and discarded the moment
         it becomes text. Recordings are never saved, and nothing you say is uploaded.</p>""",
    '<button class="btn plain">Not now</button>'
    '<button class="btn primary">Allow Microphone Access</button>',
)

# ---- 4. Accessibility ----------------------------------------------------
pages["Onboarding-Accessibility"] = onboarding(
    4, "", icon(ACCESSIBILITY, size=38, width=1.6),
    "Let Uttrflow type for you",
    "Accessibility access is how text reaches other apps.",
    """<p class="h-body">macOS asks for this because Uttrflow types into apps you have
         open. It only ever inserts at your cursor &mdash; it never reads or changes
         anything else.</p>"""
    + note(
        WARN,
        """Without this, Uttrflow still works &mdash; your text is copied to the
         clipboard for you to paste."""),
    '<button class="btn plain">Skip</button>'
    '<button class="btn primary">Open System Settings</button>',
)

# ---- 5. The speech model download, running and stopped -------------------
pages["Onboarding-Setup"] = onboarding(
    5, "", icon(DOWNLOAD, size=38, width=1.6),
    "Setting things up",
    "A one-time download, then you can start talking.",
    """<div style="width: 380px; margin-top: 20px">
         <div class="track"><i style="width: 64%"></i></div>
         <div class="row" style="justify-content: space-between; margin-top: 9px;
              font-size: var(--t-callout); color: var(--label-2)">
           <span>413 MB of 646 MB</span><span>About 1 minute left</span>
         </div>
       </div>"""
    + STAYS_ON_THIS_MAC,
    '<button class="btn plain">Cancel</button>'
    '<button class="btn primary" style="opacity: 0.4">Continue</button>',
)

# The stopped download keeps the progress it had. The installer resumes rather
# than starting over, so a bar reset to zero would be the screen lying about how
# much of the wait is left.
pages["Onboarding-Setup-Failed"] = onboarding(
    5, "", icon(REPEAT, size=36, width=1.6),
    "That download stopped",
    "Setup couldn&rsquo;t be completed. Check your connection and try again.",
    """<div style="width: 380px; margin-top: 20px">
         <div class="track"><i style="width: 64%; background: var(--label-3)"></i></div>
         <div class="row" style="justify-content: space-between; margin-top: 9px;
              font-size: var(--t-callout); color: var(--label-2)">
           <span>413 MB of 646 MB</span><span>Paused</span>
         </div>
       </div>"""
    + STAYS_ON_THIS_MAC,
    '<button class="btn plain">Not now</button>'
    '<button class="btn primary">Try Again</button>',
)

# ---- 6. The microphone check, in all five of its states ------------------
pages["Onboarding-Check"] = onboarding(
    6, "", icon(WAVEFORM, size=38, width=1.7),
    "Check your microphone",
    "Optional, and about a minute.",
    """<p class="h-body">Uttrflow measures how quiet your room is, hears how much of a
         short passage it catches, and notices which languages you speak. It does not
         change how Uttrflow hears you &mdash; nothing here teaches it anything.</p>"""
    + NOTHING_IS_KEPT,
    '<button class="btn plain">Skip</button>'
    '<button class="btn primary">Check Microphone</button>',
)

pages["Onboarding-Check-Room"] = onboarding(
    6, "", icon(EAR, size=38, width=1.6),
    "Listening to your room",
    "Stay quiet for a moment.",
    """<p class="h-body">This is the background noise Uttrflow will treat as silence,
         so it knows when you have stopped talking rather than guessing.</p>"""
    + meter(ROOM, quiet=True),
    '<button class="btn plain">Cancel</button>',
)

pages["Onboarding-Check-Reading"] = onboarding(
    6, "", icon(QUOTE, size=36, width=1.7),
    "Read this out loud",
    "In your normal voice, at your normal speed.",
    """<p class="passage">The quiet morning light came through the window while I read
         six pages and made a note of every question worth asking later.</p>"""
    + meter(SPEAKING),
    '<button class="btn plain">Cancel</button>',
)

# What the three numbers changed, rather than the three numbers. The noise floor
# is deliberately absent: it is kept, not shown, because a level in dBFS tells a
# person nothing and inviting them to read one would invite them to doubt it.
pages["Onboarding-Check-Done"] = onboarding(
    6, "good", icon(CHECK, size=38, width=1.6),
    "Your microphone is set",
    "Uttrflow caught 96% of the passage.",
    """<p class="h-body">Anything quieter than your room now counts as silence, so
         Uttrflow knows when you have finished. Your languages are set to English and
         Hindi. That reading is the starting point Insights will measure against.</p>"""
    + NOTHING_IS_KEPT,
    '<button class="btn primary">Continue</button>',
)

pages["Onboarding-Check-Failed"] = onboarding(
    6, "", icon(MIC_SLASH, size=38, width=1.6),
    "That check did not finish",
    "Recording stopped unexpectedly. Try again.",
    """<p class="h-body">You can skip it. Uttrflow works either way &mdash; the check
         only sets a starting point it can measure against later.</p>""",
    '<button class="btn plain">Skip</button>'
    '<button class="btn primary">Try Again</button>',
)

# ---- 7. Ready ------------------------------------------------------------
pages["Onboarding-Ready"] = onboarding(
    7, "good", icon(CHECK, size=38, width=1.6),
    "You&rsquo;re all set",
    "Try it right now, in this window or any other.",
    """<div class="row" style="gap: 6px; margin-top: 20px">
         <span class="key">&#8997;</span><span class="key" style="min-width: 76px">Space</span>
       </div>
       <p class="h-body" style="margin-top: 14px">Hold it, talk, let go.<br>
         Uttrflow lives in your menu bar whenever you need it.</p>""",
    '<button class="btn primary">Start Using Uttrflow</button>',
)

written = []
for stem, build in pages.items():
    written += write_pair(stem, build)
print(f"wrote {len(written)} onboarding artboards")
