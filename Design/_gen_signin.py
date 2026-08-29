"""Sign in — the first screen anyone sees, and the same screen with no network.

There is deliberately no "continue without an account". The screen therefore has
to earn the wall it puts up: it says, on the face of it, that this one step needs
the internet and that nothing after it does.

It is also step 1 of 7, and carries the same row of dots the rest of onboarding
does — drawn from the shared `dots()` helper, because a screen that counted the
steps for itself is how the row got stuck at five.

Two of the three provider buttons are drawn to their owner's published rules and
the third cannot be. Google publishes the button's own chrome — fill, 1px inside
stroke and label colour, per theme — and those exact values are set below. What
is *not* right on this artboard is the Google and GitHub marks themselves: both
are stand-ins, and both providers require their own supplied file rather than a
redrawing. See `google_mark` / `github_mark` in `_gen_shell.py`.
"""
from _gen_shell import *

# Taller than it was by the height of the dots and the air around them. The
# offline screen is what sets this: it carries the banner, three inert buttons
# and Try Again, and it is the one that runs out of window first.
W, H = 560, 566
STAGE_W, STAGE_H = 660, 760

SIGNIN_CSS = """
    .si-top { height: 38px; display: flex; align-items: center; padding: 0 14px; flex: none; }
    .si-body { flex: 1; display: flex; flex-direction: column; align-items: center;
               padding: 4px 70px 0; text-align: center; }
    .si-title { font-size: var(--t-title1); font-weight: 700; letter-spacing: -0.3px;
                margin: 16px 0 0; }
    .si-sub { font-size: var(--t-body); color: var(--label-2); margin: 7px 0 0;
              line-height: 1.45; max-width: 330px; text-wrap: pretty; }
    .provbtn { display: flex; align-items: center; justify-content: center; gap: 9px;
               width: 100%; height: 38px; border-radius: 9px; font-size: var(--t-body);
               font-weight: 500; border: 0.5px solid var(--control-border);
               background: var(--control-bg); color: var(--label);
               box-shadow: 0 0.5px 1.5px rgba(0,0,0,0.10); }
    /* Apple's mark is drawn on the opposite ground in each appearance. */
    .provbtn.apple { background: #000000; color: #FFFFFF; border-color: transparent; }
    .theme-dark .provbtn.apple { background: #FFFFFF; color: #000000; }
    /* Google publishes the button, not just the mark: these are its Light and
       Dark themes exactly — fill, 1px inside stroke, label — and the 10px the
       mark is owed before the text. Everything here is Google's number rather
       than a token of ours, which is why none of it reads from `--control-*`. */
    .provbtn.google { background: #FFFFFF; border: 1px solid #747775; color: #1F1F1F;
                      gap: 10px; padding: 0 12px; }
    .theme-dark .provbtn.google { background: #131314; border-color: #8E918F; color: #E3E3E3; }
    .stack { width: 300px; display: flex; flex-direction: column; gap: 9px; margin-top: 22px; }
    .netnote { display: flex; gap: 9px; align-items: flex-start; width: 300px;
               margin-top: 20px; padding: 10px 12px; border-radius: var(--radius-card);
               background: var(--accent-wash); font-size: var(--t-subhead);
               color: var(--label-2); line-height: 1.45; text-align: left; }
    .offline { display: flex; gap: 9px; align-items: flex-start; width: 300px;
               margin-top: 20px; padding: 10px 12px; border-radius: var(--radius-card);
               background: rgba(255,141,40,0.14); border: 0.5px solid rgba(255,141,40,0.34);
               font-size: var(--t-subhead); color: var(--label-2); line-height: 1.45;
               text-align: left; }
    .offline .warnico { color: #C25E00; }
    .theme-dark .offline .warnico { color: #FFB067; }
    .fine { font-size: var(--t-footnote); color: var(--label-3); margin: 0;
            padding: 0 0 18px; text-align: center; line-height: 1.5; flex: none; }
    .caption { width: 520px; margin: 22px auto 0; text-align: center;
               font-size: var(--t-callout); line-height: 1.55; color: rgba(0,0,0,0.50); }
    .theme-dark .caption { color: rgba(255,255,255,0.48); }
    /* The dots sit against the bottom of the body rather than in a footer:
       this page's controls are the provider buttons, so there is no row of
       verbs for them to share. The padding is not decoration — `margin-top:
       auto` is zero on the offline screen, whose banner and Try Again fill the
       body, and without it the dots land on top of that button. */
    .si-dots { margin-top: auto; padding: 20px 0 18px; }
"""


def buttons(disabled):
    dim = ' style="opacity: 0.38"' if disabled else ""
    return f"""<div class="stack">
        <div class="provbtn google"{dim}>{google_mark(18)}<span>Continue with Google</span></div>
        <div class="provbtn"{dim}>{github_mark(17)}<span>Continue with GitHub</span></div>
        <div class="provbtn apple"{dim}>{apple_mark(17)}<span>Sign in with Apple</span></div>
      </div>"""


def screen(dark, offline):
    if offline:
        middle = f"""<div class="offline">
          <span class="warnico" style="flex:none; margin-top: 1px">
            {icon(WIFI_OFF, size=15, width=1.7)}</span>
          <span><b style="font-weight:600; color: var(--label)">No internet connection.</b>
            Signing in is the one thing Uttrflow cannot do offline. Connect and try again
            &mdash; nothing else is waiting on this.</span>
        </div>
        {buttons(True)}
        <div style="margin-top: 16px"><button class="btn primary">Try Again</button></div>"""
        caption = ("Offline, the screen says exactly which step needs the network and does not "
                   "pretend a way through. The three buttons stay visible but inert, so it is "
                   "obvious what will happen the moment the connection returns.")
    else:
        middle = f"""{buttons(False)}
        <div class="netnote">
          <span style="flex:none; color: var(--accent-text); margin-top: 1px">
            {icon(GLOBE, size=15, width=1.7)}</span>
          <span>This step needs the internet. After it, Uttrflow runs entirely on this Mac
            &mdash; your speech is transcribed here and works with Wi-Fi off.</span>
        </div>"""
        caption = ("The first screen anyone sees, and step 1 of 7. There is no &ldquo;continue "
                   "without an account&rdquo;: signing in is required, and nothing on this "
                   "screen hints otherwise. What the screen owes the user in exchange is the "
                   "plain statement that this is the only moment Uttrflow needs a network. "
                   "The Google and GitHub marks here are stand-ins &mdash; both providers "
                   "require their own supplied file, and the shipped buttons must carry it.")

    html = page(
        "Sign in to Uttrflow", STAGE_W, STAGE_H,
        f"""  <div style="display: flex; flex-direction: column; align-items: center">
    <div class="win" style="width: {W}px; height: {H}px">
      <div class="si-top">{lights()}</div>
      <div class="si-body">
        {logo(46)}
        <h1 class="si-title">Sign in to Uttrflow</h1>
        <p class="si-sub">Uttrflow keeps your dictionary, your corrections and your snippets
          under one account. It needs to know which one is yours.</p>
        {middle}
        <div class="si-dots">{dots(2)}</div>
      </div>
      <p class="fine">By continuing you agree to the Terms of Use and the Privacy Policy.</p>
    </div>
    <div class="caption">{caption}</div>
  </div>""",
        extra_css=SHELL_CSS + DOTS_CSS + SIGNIN_CSS,
        pad=34,
    )
    if dark:
        html = html.replace('class="stage"', 'class="stage night theme-dark"')
    return html


written = write_pair("Sign-In", lambda dark: screen(dark, False))
written += write_pair("Sign-In-Offline", lambda dark: screen(dark, True))
print(f"wrote {len(written)} sign-in artboards")
