# Changelog

Notable changes to Uttrflow. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org).

Each released version is a git tag and a build at
[uttrflow/releases](https://github.com/uttrflow/releases).

## [Unreleased]

## [0.4.0] — 2026-09-01

### Changed
- **The floating button's meter is the microphone now.** It was seventeen bars running a
  canned loop with staggered durations — the same animation whether you shouted, whispered
  or said nothing at all. It is a real level: root mean square, mapped in decibels because
  speech sits near −30 dBFS and a linear meter spends nine tenths of its travel on the
  loudest tenth.
- **The meter is a recording rather than a decoration.** Capsules, mirrored about a centre
  line, one per arrival, walking from the edge where sound comes in toward the mark — so
  the horizontal axis is time and every bar on screen is a moment that was actually said.
  Bars past half scale take the accent teal.
- **Listening went from 286 × 52 points to 136 × 32**, and working is identical to it so
  the panel cannot change shape at the instant the key is released. The old width was what
  a sixty-character transcript preview and a recovery button need, paid on every dictation
  for a state listening never enters.
- **A success needs no words.** Inserted, copied and nothing-heard were a 286-point panel
  each; they are a 26-point disc, an expanding ⌘V keycap and a struck level. When the text
  has landed in the document, a panel repeating it narrates something you are already
  looking at. Only a blocked microphone stays wide, because it is the one with something to
  do about it.
- **Inserted is the mark opening into a checkmark.** Both are one round-capped stroke — a
  short arm, a turn, a long arm — so confirming an insertion needs no second glyph.
- The resting grip is three dots rather than five, and 34 points tall rather than 46.

### Fixed
- **The resting grip had a box drawn round it, and in fact two.** Every form was built on
  the same translucent slab, whose hairline and 34%-black shadow read as depth around a
  pill and as an outline nobody meant to draw around nine points of dots — and the panel
  was drawing a second ring outside the first. Both are gone; the dots keep a half-point
  shadow so they hold on a pale wallpaper, and the hit target is unchanged because it never
  came from the slab.
- Working no longer loops. A loop says *indefinite*, which is the animation of a download
  with no progress bar; tidying up a sentence takes about a second and always ends, so it
  now plays once and resolves into the tick.

## [0.3.0] — 2026-08-30

### Added
- **Any modifier combination can be the dictation shortcut** — ⌃⌥, ⌘⌥, or a single
  modifier on its own. Only Fn was allowed before, on an argument about ⌘ that had been
  applied to every modifier-only binding.
- **Updates in Settings**: the version, a Check Now button, and a switch for whether an
  update installs itself or asks first. Updating was reachable only from the menu bar.
- **The menu bar says when an update is happening.** Downloading, waiting for a quiet
  moment, and installing each say so. Before this the app replaced itself and relaunched
  in silence, which reads as a crash.
- Continuous integration on every pull request, and a tag-driven release workflow.
- `CONTRIBUTING.md`, `RELEASING.md`, `SECURITY.md` and a code of conduct.
- `Docs/measuring-accuracy.md` — what it would actually take to measure a speech-engine
  change, which turns out to be fifteen minutes rather than the sixteen hours assumed.

### Fixed
- The "install updates automatically" preference is now read at launch. It was hardcoded
  on, so any change to it was forgotten the next time the app started.
- The shortcut field's refusal no longer says "Try a letter, a number or Space" to
  somebody who pressed a perfectly ordinary modifier combination.

## [0.2.2] — 2026-08-29

First public release of the source. The app itself has been shipping since 0.1.0; this is
where its code became readable.

### Added
- Work on this Mac without an Uttrflow account, using the name macOS already knows you by.
  Sign-in was the one screen that could not work offline; it now has a way through that
  needs nothing.
- Automatic updates through Sparkle, checked against a key compiled into each build.
- A Position Monitoring view, and version reporting at the foot of the sidebar.

### Fixed
- The sidebar no longer claims a session nobody has.
- One retention window now governs both copies of a transcript, rather than two that could
  disagree.

[Unreleased]: https://github.com/uttrflow/uttrflow-swift/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.4.0
[0.3.0]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.3.0
[0.2.2]: https://github.com/uttrflow/uttrflow-swift/releases/tag/v0.2.2
