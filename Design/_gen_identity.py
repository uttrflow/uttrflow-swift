from _gen_common import *

ID_CSS = """
    .stage.id { background: #EFEFF3; display: block;
      background-image: linear-gradient(180deg, #F5F4F8 0%, #E9E8EE 100%); }
    .sect { font-size: var(--t-subhead); font-weight: 600; letter-spacing: 0.4px;
            text-transform: uppercase; color: var(--label-3); margin: 0 0 4px; }
    .sect-d { font-size: var(--t-callout); color: var(--label-2); margin: 0 0 16px;
              max-width: 560px; line-height: 1.45; }
    /* macOS app icons are a superellipse; 22.4% is the closest border-radius gets. */
    .appicon { border-radius: 22.4%; display: flex; align-items: center; justify-content: center;
      background: linear-gradient(180deg, #1B2024 0%, #0A0D0F 100%);
      box-shadow: 0 6px 18px rgba(0,0,0,0.22), 0 1px 2px rgba(0,0,0,0.12),
                  inset 0 0 0 0.5px rgba(242,241,236,0.12); }
    .icon-cap { font-size: var(--t-footnote); color: var(--label-3); text-align: center;
                margin-top: 9px; font-variant-numeric: tabular-nums; }
    .swatch-row { display: flex; gap: 0; border-radius: var(--radius-card); overflow: hidden;
                  box-shadow: 0 1px 3px rgba(0,0,0,0.10); }
    .sw-cell { width: 106px; padding: 12px 12px 11px; }
    .sw-cell .n { font-size: var(--t-footnote); font-weight: 600; }
    .sw-cell .h { font-size: var(--t-footnote); opacity: 0.72; margin-top: 1px;
                  font-variant-numeric: tabular-nums; }
    .sw-cell .u { font-size: 9px; opacity: 0.62; margin-top: 5px; line-height: 1.35; }
    .surface { border-radius: var(--radius-card); padding: 20px 24px; display: flex;
               align-items: center; gap: 18px; }
    .barstrip { height: 26px; border-radius: 8px; display: flex; align-items: center; gap: 16px;
      padding: 0 12px; background: rgba(255,255,255,0.16); color: rgba(255,255,255,0.86);
      backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px); }
    .darkfield { border-radius: var(--radius-card);
      background-image: radial-gradient(120% 120% at 20% 0%, #4A6773 0%, #2B4049 100%); }
    .note { font-size: var(--t-footnote); color: var(--label-2); line-height: 1.5; }
"""

SIZES = [(112, "512pt"), (64, "128pt"), (40, "64pt"), (24, "32pt")]
icons = ""
for px, label in SIZES:
    icons += f"""      <div>
        <div class="appicon" style="width: {px}px; height: {px}px">{logo(round(px * 0.56), fill="#F2F1EC")}</div>
        <div class="icon-cap">{label}</div>
      </div>\n"""

RAMP = [
    ("Mark", "#101316", "#FFFFFF", "The mark's ink. Never used for interface text."),
    ("Signal", "#17A398", "#0B1F1D", "The listening state, and only that. Never the resting logo."),
    ("Accent", "#128077", "#FFFFFF", "Fills that carry white text. 4.80:1 — the lightest that passes."),
    ("Light", "#39D0C4", "#1D1D1F", "Switches, progress, waveform, charts. No text sits on it."),
    ("Tint", "#9EDCD7", "#1D1D1F", "Large decorative fills."),
    ("Wash", "#EFF8F7", "#1D1D1F", "Tinted backgrounds and callouts."),
    ("Bright", "#5FE0D3", "#1D1D1F", "The accent as a foreground: waveform bars, second chart series."),
]
swatches = "".join(
    f'<div class="sw-cell" style="background: {bg}; color: {fg}">'
    f'<div class="n">{n}</div><div class="h">{bg}</div><div class="u">{u}</div></div>'
    for n, bg, fg, u in RAMP
)

body = f"""  <div>
    <p class="sect">App icon</p>
    <p class="sect-d">An ink tile carrying the mark. In a Dock of saturated squares the quiet
      one is the one you find, and at 32&nbsp;points the mark is still a mark rather than a
      smudge.</p>
    <div class="row" style="gap: 26px; align-items: flex-end">
{icons}    </div>

    <div style="height: 26px"></div>
    <p class="sect">The mark on either background</p>
    <p class="sect-d">A lowercase <i>u</i> with deliberately uneven stems &mdash; a letter and a
      waveform at once. One continuous stroke with round caps and no enclosed counter, which is
      what lets it hold its shape all the way down to a favicon.</p>
    <div class="row" style="gap: 16px; align-items: stretch">
      <div class="surface" style="background: #FFFFFF; box-shadow: 0 1px 3px rgba(0,0,0,0.08)">
        {logo(52, fill="var(--logo-ink)")}
        <div><div style="font-weight: 600">On light</div>
          <div class="note">The ink, #101316.</div></div>
      </div>
      <div class="surface darkfield">
        {logo(52, fill="#F2F1EC")}
        <div style="color: rgba(255,255,255,0.92)"><div style="font-weight: 600">On dark</div>
          <div class="note" style="color: rgba(255,255,255,0.62)">Chalk, #F2F1EC &mdash; the mark
            reverses rather than tinting.</div></div>
      </div>
    </div>

    <div style="height: 26px"></div>
    <p class="sect">In the menu bar</p>
    <div class="row" style="gap: 18px; align-items: center">
      <div class="darkfield" style="padding: 14px 16px">
        <div class="barstrip" style="width: 178px">
          <span style="opacity:0.42">{icon(GLOBE, size=15, width=1.5)}</span>
          <span style="opacity:0.42">{icon(MIC, size=16, width=1.5)}</span>
          {logo(16, fill="currentColor")}
          <span style="margin-left:auto; font-size: 11px; opacity:0.42">9:41</span>
        </div>
      </div>
      <p class="note" style="flex: 1; max-width: 420px">At rest the slot carries the mark, shipped
        as a template image so the system tints it for a light or dark bar. While dictation is
        actually running the icon becomes the state &mdash; listening, tidying, inserted &mdash;
        because a menu bar symbol earns its place by saying what the app is <i>doing</i>.</p>
    </div>

    <div style="height: 26px"></div>
    <p class="sect">Teal ramp</p>
    <div class="swatch-row">{swatches}</div>
  </div>"""

with open("Identity.dc.html", "w") as handle:
    handle.write(
        page("Identity", 900, 780, body, extra_css=ID_CSS, pad=38).replace(
            'class="stage"', 'class="stage id"'
        )
    )
print("wrote Identity.dc.html")
