from _gen_common import *

ERR_CSS = """
    .stage.err { background: #EFEFF3; display: block;
      background-image: linear-gradient(180deg, #F4F4F8 0%, #E9E9EF 100%); }
    .sect { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
            text-transform: uppercase; color: var(--label-3); margin: 0 0 12px; }
    .banner { display: flex; gap: 12px; padding: 14px 15px; border-radius: var(--radius-card);
              background: #FFFFFF; border: 0.5px solid var(--separator);
              box-shadow: 0 1px 3px rgba(0,0,0,0.06); width: 396px; }
    .tile { width: 30px; height: 30px; border-radius: 9px; flex: none; display: flex;
            align-items: center; justify-content: center; color: #FFFFFF; }
    .banner .t { font-size: var(--t-body); font-weight: 600; }
    .banner .b { font-size: var(--t-callout); color: var(--label-2); margin-top: 4px;
                 line-height: 1.45; }
    .banner .acts { display: flex; gap: 8px; margin-top: 11px; }
    .cap { font-size: var(--t-footnote); color: var(--label-3); margin: 8px 0 0 42px; width: 354px;
           line-height: 1.45; }
    .grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 26px 32px; }
"""


def banner(color, glyph, title, body, actions, caption):
    acts = "".join(actions)
    return f"""<div>
        <div class="banner">
          <div class="tile" style="background: {color}">{icon(glyph, size=17, width=1.9)}</div>
          <div style="flex:1; min-width:0">
            <div class="t">{title}</div>
            <div class="b">{body}</div>
            <div class="acts">{acts}</div>
          </div>
        </div>
        <div class="cap">{caption}</div>
      </div>"""


P = '<button class="btn sm primary">%s</button>'
S = '<button class="btn sm">%s</button>'
L = '<button class="btn sm plain">%s</button>'

cards = [
    banner("#FF383C", MIC, "Microphone access is turned off",
           "Uttrflow cannot hear you until macOS lets it use the microphone.",
           [P % "Open System Settings", L % "Learn why"],
           "Blocking. Dictation is disabled rather than failing silently when you press the key."),
    banner("#FF8D28", ACCESSIBILITY, "Uttrflow can&rsquo;t type into other apps",
           "Without Accessibility access, finished text is copied to your clipboard "
           "instead of being typed for you.",
           [P % "Open System Settings", S % "Keep using the clipboard"],
           "Degraded, not broken. The product still does its job &mdash; you press &#8984;V."),
    banner("#FF8D28", DOWNLOAD, "Setup couldn&rsquo;t finish",
           "The download stopped at 413 MB. This is the only step that needs the internet.",
           [P % "Try Again", S % "Do this later"],
           "Recoverable. Progress is kept, so retrying resumes rather than restarting."),
    banner("#8E8E93", MIC, "We didn&rsquo;t catch that",
           "That was under half a second of sound. Hold the shortcut while you talk, "
           "and let go when you&rsquo;re done.",
           [S % "Got it"],
           "Not an error, and worded so it doesn&rsquo;t read like one. Auto-dismisses."),
    banner("#FF8D28", WARN, "Nowhere to put the text",
           "Nothing on screen accepts typing right now, so your words are on the clipboard.",
           [P % "Paste", S % "Copy again"],
           "The transcript is never lost. Every insertion failure ends with the text in hand."),
    banner("#128077", SPARKLE, "Couldn&rsquo;t tidy that up",
           "Your words were captured exactly as you said them, just without the clean-up.",
           [P % "Insert as-is", S % "Copy"],
           "Clean-up is the only optional stage. Failing it degrades quality, never output."),
]

body = f"""  <div>
    <p class="sect">Errors and repair states</p>
    <div class="grid">
      {"".join(cards)}
    </div>
    <div style="margin-top: 26px; padding: 13px 15px; border-radius: var(--radius-card);
         background: rgba(0,0,0,0.035); font-size: var(--t-callout); color: var(--label-2);
         line-height: 1.55; max-width: 824px">
      Every failure carries its own sentence and its own single next action, so there is one
      way of showing a problem rather than six. None of them asks the user to understand
      anything about how Uttrflow works.
    </div>
  </div>"""

with open("Errors.dc.html", "w") as handle:
    handle.write(
        page("Errors", 900, 700, body, extra_css=ERR_CSS, pad=38).replace(
            'class="stage"', 'class="stage err"'
        )
    )
print("wrote Errors.dc.html")
