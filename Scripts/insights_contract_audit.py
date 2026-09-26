#!/usr/bin/env python3
"""Fails when the Insights artboard generator disagrees with InsightsPresentation.

#1144 found the Insights artboards inventing a "Languages you spoke" card with no source,
restoring the removed Accuracy baseline meter, and drawing a selectable-looking scope popup
where production shows a plain "Last N days" label. Nothing tied `Design/_gen_app.py`'s
Insights section to `Sources/UttrflowUX/InsightsPresentation.swift`, so a controlled
regeneration reproduced every mismatch byte-for-byte.

This reads both sides — the generator source and the presenter it is meant to draw — and
fails on any of the five things #1144 asked for:

1. The scope is a non-selectable label ("Last N days"), never a `pop()` popup, and its
   day count is the same `RETENTION_DAYS` the bars are sized from, not a separate literal.
2. The Accuracy tile uses `DictationPresenter.accuracyTitle` / `accuracyCaption` verbatim,
   with a single "Now" meter and no "Baseline" row.
3. No "Languages you spoke" card, or any language-breakdown vocabulary.
4. The chart draws an average line/label (`.avgline`, "N a day").
5. Each place row shows both a word count and a percentage.

Needs no build: it is a source-level check, like `design_contrast_audit.py`.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
GEN_APP_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_app.py")
DICTATION_PRESENTER_SOURCE = os.path.join(
    REPO_ROOT, "Sources", "UttrflowUX", "MainDictationPresentation.swift"
)
INSIGHTS_PRESENTER_SOURCE = os.path.join(
    REPO_ROOT, "Sources", "UttrflowUX", "InsightsPresentation.swift"
)

SECTION_START = "# Insights — only what the app already measures."


def insights_section(text):
    """The generator's Insights block, so a Dictation-only string (#1139) is not caught here."""
    start = text.find(SECTION_START)
    if start == -1:
        raise SystemExit(f"insights contract audit: no {SECTION_START!r} marker in {GEN_APP_SOURCE}")
    # The title line is itself framed by a rule above and below, as every section header is —
    # skip past that closing rule before looking for the *next* section's opening one.
    body_start = text.find("\n", start + len(SECTION_START))
    body_start = text.find("\n", body_start + 1)
    end = text.find("\n# =====", body_start)
    if end == -1:
        raise SystemExit("insights contract audit: could not find the end of the Insights section")
    return text[start:end]


def swift_string_constant(text, name):
    # A `static let name = "..."` or a triple-quoted `static let name = ...` block.
    triple = re.search(
        rf'static let {re.escape(name)}\s*=\s*"""\s*(?P<body>.*?)\s*"""', text, re.DOTALL
    )
    if triple:
        # Swift's `\` line-continuation joins wrapped lines back into one sentence.
        return re.sub(r"\s*\\\s*\n\s*", " ", triple.group("body")).replace("\n", " ").strip()
    single = re.search(rf'static let {re.escape(name)}\s*=\s*"(?P<body>[^"]*)"', text)
    if single:
        return single.group("body")
    raise SystemExit(f"insights contract audit: no `{name}` constant found in {DICTATION_PRESENTER_SOURCE}")


def to_html_entities(text):
    """The design source writes curly quotes and dashes as HTML entities, not literal glyphs."""
    return (
        text.replace("“", "&ldquo;")
        .replace("”", "&rdquo;")
        .replace("—", "&mdash;")
    )


def collapse_whitespace(text):
    return re.sub(r"\s+", " ", text).strip()


def self_test():
    ok = True
    section = insights_section(open(GEN_APP_SOURCE).read())
    if "Last {RETENTION_DAYS} days" not in section:
        print(
            "  ✗ self-test: RETENTION_DAYS no longer feeds the scope title — "
            "either the fixture changed shape or this audit's marker is stale",
            file=sys.stderr,
        )
        ok = False
    if "assert len(DAYS) == RETENTION_DAYS" not in section:
        print(
            "  ✗ self-test: the DAYS/RETENTION_DAYS assertion is missing — "
            "the bars could silently stop matching the declared window",
            file=sys.stderr,
        )
        ok = False
    return ok


def audit():
    findings = []

    app_source = open(GEN_APP_SOURCE).read()
    section = insights_section(app_source)
    dictation_source = open(DICTATION_PRESENTER_SOURCE).read()
    insights_source = open(INSIGHTS_PRESENTER_SOURCE).read()

    # ---- 1. A non-selectable scope, sized from the one retention window. -----------------
    if re.search(r'pop\(\s*["\']', section):
        findings.append(
            "the Insights toolbar still builds a `pop()` popup; production's scope has no "
            "chevron or menu — see InsightsPresentation.swift:167-168 and "
            "InsightsPresentationTests.swift:82-87 (`isSelectable == false`)"
        )
    if "scopelabel(SCOPE_TITLE)" not in app_source:
        findings.append(
            "the Insights screens no longer pass a single `SCOPE_TITLE` to `scopelabel()` — "
            "the populated and empty variants must show the same non-selectable window"
        )
    if not re.search(r"RETENTION_DAYS\s*=\s*\d+", section):
        findings.append(
            "no single `RETENTION_DAYS` constant in the Insights section — #1144 was the bars "
            "and the scope label each hard-coding the window separately"
        )
    if "assert len(DAYS) == RETENTION_DAYS" not in section:
        findings.append(
            "the day-bar fixture (`DAYS`) is not asserted against `RETENTION_DAYS`, so the "
            "bars drawn and the scope's day count can silently diverge again"
        )

    # ---- 2. Left as dictated, one Now meter, no Baseline. ---------------------------------
    accuracy_title = swift_string_constant(dictation_source, "accuracyTitle")
    accuracy_caption = swift_string_constant(dictation_source, "accuracyCaption")
    if accuracy_title not in section:
        findings.append(
            f"the Accuracy tile does not say {accuracy_title!r} "
            "(DictationPresenter.accuracyTitle, shared with Insights at "
            "InsightsPresentation.swift:262)"
        )
    if to_html_entities(accuracy_caption) not in collapse_whitespace(section):
        findings.append(
            "the Accuracy tile's explanation does not match DictationPresenter.accuracyCaption "
            "verbatim (InsightsPresentation.swift:264)"
        )
    if re.search(r"Baseline", section):
        findings.append(
            'a "Baseline" row remains in the Insights section — production shows a single '
            '"Now" meter and no baseline comparison (InsightsPresentationTests.swift:126-140)'
        )
    if "Accuracy</div>" in section:
        findings.append(
            'the Accuracy tile is still titled "Accuracy" rather than the shared '
            '"Left as dictated" wording'
        )

    # ---- 3. No invented language breakdown. -----------------------------------------------
    for banned in ("Languages you spoke", "Hinglish", "LANGS ="):
        if banned in section:
            findings.append(
                f"{banned!r} still appears in the Insights section — no language measurement "
                "exists and the contract omits the card entirely "
                "(InsightsPresentation.swift:144-145; InsightsPresentationTests.swift:100-108)"
            )

    # ---- 4. The average line and its label. -----------------------------------------------
    if "avgline" not in section:
        findings.append(
            "no `.avgline` element in the Insights section — production draws a dashed "
            "average line and label over the bars (InsightsPageView.swift:113-133; "
            "InsightsPresentationTests.swift:233-274)"
        )
    if "a day" not in section:
        findings.append('no "N a day" average label in the Insights section')

    # ---- 5. Word counts alongside each place's percentage. --------------------------------
    if not re.search(r"for i,\s*\(n,\s*p,\s*w\)\s*in enumerate\(PLACES\)", section):
        findings.append(
            "PLACES rows no longer carry a word count alongside the share — production shows "
            "both (InsightsPageView.swift:60-68; InsightsPresentationTests.swift:282-292)"
        )

    # ---- Cross-check the scope wording against the presenter itself. ----------------------
    if not re.search(r'title:\s*"Last\s*\\?\(', insights_source):
        findings.append(
            "InsightsPresentation.swift no longer builds its scope title as \"Last N days\" — "
            "update this audit's expectations to match the new contract, not just the artboard"
        )

    print("Insights artboard vs InsightsPresentation contract")
    if findings:
        print(f"\n  ✗ {len(findings)} mismatch(es):", file=sys.stderr)
        for finding in findings:
            print(f"    - {finding}", file=sys.stderr)
        return 1

    print("  ✓ scope, Accuracy tile, language card, average line and place rows all match\n")
    print(
        "insights contract audit: Design/_gen_app.py's Insights section matches "
        "InsightsPresentation and InsightsPresentationTests.\n"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the section-extraction and RETENTION_DAYS checks still fire",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\ninsights contract audit: self-test failed; the section markers are stale.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())
