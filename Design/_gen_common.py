"""Shared building blocks for the Uttrflow design artboards.

Every colour and type size here was read off macOS 26.5 at design time via
NSColor / NSFont.preferredFont, not estimated.
"""

TOKENS = """
    :root {
      /* Read from NSColor on macOS 26.5, sRGB. */
      --label: rgba(0,0,0,0.847);
      --label-2: rgba(0,0,0,0.498);
      --label-3: rgba(0,0,0,0.259);
      --label-4: rgba(0,0,0,0.098);
      --separator: rgba(0,0,0,0.098);
      --window-bg: #FFFFFF;
      --sidebar-bg: rgba(246,246,248,0.94);
      --fill: rgba(0,0,0,0.05);
      --fill-2: rgba(0,0,0,0.08);
      /* Teal ramp, hue 175 — derived from the mark's signal teal (#17A398).
         The brand teal itself only reaches 3.1:1 on white, so it stays a mark
         and state colour and never carries interface text; this ramp is what
         fills use. White 13px text needs 4.5:1, which caps a text-bearing fill
         at 29% lightness. Everything that carries no text goes lighter, which
         is most of the surface area, so the interface still reads light. */
      --accent: #128077;         /* fills with white text on them — 4.80:1 */
      --accent-pressed: #0E645D;
      --accent-light: #39D0C4;   /* controls and graphics with no text */
      --accent-tint: #9EDCD7;    /* large decorative fills */
      --accent-wash: #EFF8F7;    /* tinted backgrounds */
      --accent-dark: #29C0B4;    /* on dark surfaces — 7.4:1 on #1E1E1E */
      --logo-ink: #101316;       /* the mark's ink; chalk on dark, see _gen_shell */
      /* The accent as a foreground rather than a fill: waveform bars, the second
         series in a chart. A lighter weight of the one accent, not a second hue —
         the identity is ink, chalk, signal and slate, and a fifth colour invented
         for contrast is how a palette stops meaning anything. */
      --accent-2: #5FE0D3;
      --accent-2-deep: #0E645D;
      --red: #FF383C;
      --green: #34C759;

      /* NSFont.preferredFont point sizes, macOS 26.5. */
      --t-large-title: 26px;
      --t-title1: 22px;
      --t-title2: 17px;
      --t-title3: 15px;
      --t-body: 13px;
      --t-callout: 12px;
      --t-subhead: 11px;
      --t-footnote: 10px;

      --radius-window: 14px;
      --radius-control: 7px;
      --radius-card: 10px;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, "SF Pro Text", system-ui, sans-serif;
      font-size: var(--t-body);
      color: var(--label);
      -webkit-font-smoothing: antialiased;
    }
    a { color: var(--accent); }
    a:hover { color: var(--accent-pressed); }
    .stage {
      display: flex; align-items: center; justify-content: center;
      background: #E8E8ED;
      background-image: radial-gradient(120% 120% at 20% 0%, #F2F1F6 0%, #DFDEE6 60%, #CFCEDA 100%);
    }
    .win {
      background: var(--window-bg);
      border-radius: var(--radius-window);
      box-shadow: 0 22px 60px rgba(0,0,0,0.24), 0 2px 6px rgba(0,0,0,0.12),
                  0 0 0 0.5px rgba(0,0,0,0.16);
      overflow: hidden;
      display: flex; flex-direction: column;
    }
    .lights { display: flex; gap: 8px; align-items: center; }
    .light { width: 12px; height: 12px; border-radius: 50%; }
    .btn {
      display: inline-flex; align-items: center; justify-content: center; gap: 6px;
      height: 28px; padding: 0 14px; border-radius: var(--radius-control);
      font-size: var(--t-body); font-weight: 500; white-space: nowrap;
      border: 0.5px solid rgba(0,0,0,0.14); background: #FFFFFF;
      box-shadow: 0 0.5px 1px rgba(0,0,0,0.08);
      color: var(--label);
    }
    .btn.primary {
      background: var(--accent); color: #FFFFFF; border-color: transparent;
      box-shadow: 0 1px 2px rgba(0,0,0,0.14);
    }
    .btn.plain { background: transparent; border-color: transparent; box-shadow: none; color: var(--accent); }
    .btn.destructive { color: var(--red); }
    .btn.sm { height: 22px; padding: 0 10px; font-size: var(--t-callout); }
    .key {
      display: inline-flex; align-items: center; justify-content: center;
      min-width: 24px; height: 24px; padding: 0 7px;
      border-radius: 6px; background: #FFFFFF;
      border: 0.5px solid rgba(0,0,0,0.18);
      box-shadow: 0 1px 0 rgba(0,0,0,0.10), inset 0 -1px 0 rgba(0,0,0,0.04);
      font-size: var(--t-callout); font-weight: 500; color: var(--label);
    }
    .muted { color: var(--label-2); }
    .faint { color: var(--label-3); }
    .row { display: flex; align-items: center; }
    .hr { height: 0.5px; background: var(--separator); }
"""


def page(title, width, height, body, extra_css="", pad=40):
    """Wraps artboard markup in the Design Component envelope."""
    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <style>{TOKENS}{extra_css}</style>
</helmet>
<div class="stage" style="width: {width}px; height: {height}px; padding: {pad}px">
{body}
</div>
</x-dc>
<script data-dc-script data-props='{{"$preview":{{"width":{width},"height":{height}}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
"""


#: The mark, as one closed outline on a 100x100 grid: a lowercase u with uneven
#: stems, drawn as a round-capped stroke and then outlined so it needs no
#: stroke-width to scale with it. Authored in the identity kit; the same path
#: ships in uttrflow-brand/svg and in tokens.json, so change it in one place.
MARK_PATH = ("M19 37 L19 55 A31 31 0 0 0 81 55 L81 21 A7 7 0 0 0 67 21 "
             "L67 55 A17 17 0 0 1 33 55 L33 37 A7 7 0 0 0 19 37 Z")
MARK_VIEWBOX = "19 14 62 72"
MARK_ASPECT = 62 / 72


def logo(size, opacity=1.0, fill="var(--logo-ink)"):
    """The Uttrflow mark, inline so it takes the theme's ink rather than
    shipping a second file per colour. `size` is the drawn height."""
    return (f'<svg width="{round(size * MARK_ASPECT, 2)}" height="{size}" '
            f'viewBox="{MARK_VIEWBOX}" fill="none" role="img" aria-label="Uttrflow" '
            f'style="display: block; opacity: {opacity}">'
            f'<path d="{MARK_PATH}" fill="{fill}"/></svg>')


def lights():
    return """<div class="lights">
        <span class="light" style="background:#FF5F57"></span>
        <span class="light" style="background:#FEBC2E"></span>
        <span class="light" style="background:#28C840"></span>
      </div>"""


# ---- the onboarding progress indicator -----------------------------------
# Shared rather than owned by the onboarding generator, because sign-in is the
# first step and is drawn by a different one. Two files each counting the steps
# for themselves is exactly how the row of dots fell out of step with the flow
# the last time.

#: How many pages first-run onboarding has — `OnboardingStep.count`.
STEP_COUNT = 7

DOTS_CSS = """
    .dots { display: flex; gap: 6px; align-items: center; }
    /* Three states, not two. At five steps a pair of greys was countable; at
       seven it is not, so the page you are on is an accent pill and the pages
       behind you are darker than the ones ahead. */
    .dot { width: 6px; height: 6px; border-radius: 3px; background: var(--label-4); }
    .dot.done { background: var(--label-3); }
    .dot.on { width: 18px; background: var(--accent); }
    .theme-dark .dot.on { background: var(--accent-dark); }
"""


def dots(step, count=STEP_COUNT):
    """The row of dots, with `step` 1-based — `OnboardingStep.position`."""
    marks = ""
    for i in range(1, count + 1):
        state = "dot on" if i == step else ("dot done" if i < step else "dot")
        marks += f'<span class="{state}"></span>'
    return f'<div class="dots" aria-label="Step {step} of {count}">{marks}</div>'


def icon(paths, size=20, stroke="currentColor", width=1.5, fill="none"):
    """Stroke-based SVG icon on a 24-grid."""
    return (
        f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="{fill}" '
        f'stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" '
        f'stroke-linejoin="round">{paths}</svg>'
    )


MIC = '<path d="M12 3.5a3 3 0 0 0-3 3v5a3 3 0 0 0 6 0v-5a3 3 0 0 0-3-3z"/><path d="M5.5 10.5v1a6.5 6.5 0 0 0 13 0v-1"/><path d="M12 18v3"/>'
CHECK = '<path d="M4.5 12.5l5 5 10-11"/>'
WARN = '<path d="M12 4.5 2.8 20h18.4L12 4.5z"/><path d="M12 10v4.5"/><path d="M12 17.4v.1"/>'
SPARKLE = '<path d="M12 3.5l1.9 5.1 5.1 1.9-5.1 1.9L12 17.5l-1.9-5.1L5 10.5l5.1-1.9L12 3.5z"/><path d="M18.5 15.5l.7 1.9 1.9.7-1.9.7-.7 1.9-.7-1.9-1.9-.7 1.9-.7.7-1.9z"/>'
GEAR = '<circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v2.4M12 18.8v2.4M21.2 12h-2.4M5.2 12H2.8M18.5 5.5l-1.7 1.7M7.2 16.8l-1.7 1.7M18.5 18.5l-1.7-1.7M7.2 7.2 5.5 5.5"/>'
CLOCK = '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.2V12l3.2 2"/>'
GAUGE = '<path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4.2-5"/>'
LOCK = '<rect x="4.8" y="10.5" width="14.4" height="9.5" rx="2.2"/><path d="M8.5 10.5V7.8a3.5 3.5 0 0 1 7 0v2.7"/>'
GLOBE = '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5c2.2 2.4 3.3 5.4 3.3 8.5s-1.1 6.1-3.3 8.5c-2.2-2.4-3.3-5.4-3.3-8.5S9.8 5.9 12 3.5z"/>'
DOWNLOAD = '<path d="M12 4v11"/><path d="M7.5 10.5 12 15l4.5-4.5"/><path d="M4.5 19.5h15"/>'
ACCESSIBILITY = '<circle cx="12" cy="4.6" r="1.9"/><path d="M4.6 8.3h14.8"/><path d="M9.4 8.3v3.6l-2 8"/><path d="M14.6 8.3v3.6l2 8"/>'
