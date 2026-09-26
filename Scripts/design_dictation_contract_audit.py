#!/usr/bin/env python3
"""Fails when the Dictation artboards drift from `DictationPresenter`'s own figures.

#153 renamed the populated rail's cleanup-ratio tile from "Accuracy" to
`DictationPresenter.accuracyTitle` ("Left as dictated"), said plainly in
`accuracyCaption` that the figure does not say whether words were heard correctly, and
drew only today's meter with no baseline row. #1139 found the design generator had
drifted back to all three: a 97.2% "Accuracy" tile, a restored "Baseline" meter, and a
per-row context field the app has nowhere to store.

This reads `DictationPresenter`'s `accuracyTitle` and `accuracyCaption` out of
`MainDictationPresentation.swift` and fails unless `Design/_gen_app.py`'s Dictation
section spells them verbatim, and fails outright if that section still spells the
retired "Accuracy" label or draws a second ("Baseline") meter row — so neither can
silently return.
"""

import argparse
import os
import re
import sys


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
PRESENTER_SOURCE = os.path.join(
    REPO_ROOT, "Sources", "UttrflowUX", "MainDictationPresentation.swift"
)
GENERATOR_SOURCE = os.path.join(REPO_ROOT, "Design", "_gen_app.py")

TITLE_DECL = re.compile(r'static let accuracyTitle = "(?P<title>[^"]+)"')
CAPTION_DECL = re.compile(r'static let accuracyCaption = """\n(?P<body>.*?)\n\s*"""', re.S)
NOT_A_WORD_CHAR = r"(?<![A-Za-z])"  # a whole-word match, since "inaccuracy" is not the label


def load_presenter_strings(path):
    """Returns (accuracyTitle, accuracyCaption) exactly as `DictationPresenter` declares them."""
    text = open(path).read()
    title_match = TITLE_DECL.search(text)
    if not title_match:
        raise SystemExit(
            f"dictation contract audit: no accuracyTitle declaration found in {path}"
        )
    caption_match = CAPTION_DECL.search(text)
    if not caption_match:
        raise SystemExit(
            f"dictation contract audit: no accuracyCaption declaration found in {path}"
        )
    # A Swift `"""` literal joins a trailing `\` continuation into one line, same as the
    # compiler; the space before the `\` is already text, so the join itself adds none.
    caption = re.sub(r"\\\n\s*", "", caption_match.group("body")).strip()
    return title_match.group("title"), caption


def dictation_section(path):
    """The generator's Dictation section: from `DICTATIONS = [` to the Dictionary heading.

    Whitespace is collapsed, since the generator wraps a caption's literal across source
    lines for readability the same way `MainDictationPresentation.swift` does — the wrap
    itself carries no meaning, so neither side should have to match the other's line breaks.
    """
    text = open(path).read()
    start = text.find("DICTATIONS = [")
    end = text.find("# Dictionary", start)
    if start == -1 or end == -1:
        raise SystemExit(
            f"dictation contract audit: could not isolate the Dictation section of {path}"
        )
    return re.sub(r"\s+", " ", text[start:end])


def audit_failures(section, title, caption):
    failures = []

    if title not in section:
        failures.append(
            f"the generator's Dictation rail never spells accuracyTitle ({title!r}) verbatim"
        )

    if caption not in section:
        failures.append(
            "the generator's Dictation rail never spells accuracyCaption verbatim "
            f"({caption!r})"
        )

    if re.search(NOT_A_WORD_CHAR + r"Accuracy(?![A-Za-z])", section):
        failures.append(
            'the generator\'s Dictation section still spells the retired "Accuracy" label'
        )

    if re.search(NOT_A_WORD_CHAR + r"Baseline(?![A-Za-z])", section):
        failures.append(
            'the generator\'s Dictation section still draws a "Baseline" meter row'
        )

    return failures


def audit_pairs():
    if not os.path.isfile(PRESENTER_SOURCE):
        raise SystemExit(f"dictation contract audit: {PRESENTER_SOURCE} not found")
    if not os.path.isfile(GENERATOR_SOURCE):
        raise SystemExit(f"dictation contract audit: {GENERATOR_SOURCE} not found")

    title, caption = load_presenter_strings(PRESENTER_SOURCE)
    section = dictation_section(GENERATOR_SOURCE)
    return audit_failures(section, title, caption)


def self_test():
    """Proves the extractors resolve a known-good fixture and the regressions they catch."""
    fixture = (
        '    static let accuracyTitle = "Left as dictated"\n'
        '    static let accuracyCaption = """\n'
        "        The share of your words the clean-up left exactly as you said them. It does not say \\\n"
        "        whether they were heard correctly.\n"
        '        """\n'
    )
    ok = True

    title_match = TITLE_DECL.search(fixture)
    caption_match = CAPTION_DECL.search(fixture)
    if not title_match or title_match.group("title") != "Left as dictated":
        print("  ✗ self-test: accuracyTitle extraction failed", file=sys.stderr)
        ok = False
    if not caption_match:
        print("  ✗ self-test: accuracyCaption extraction failed", file=sys.stderr)
        ok = False

    good_section = (
        'DICTATIONS = [\n]\n<div class="k">Left as dictated</div>\n'
        '<div class="c">The share of your words the clean-up left exactly as you said them. '
        "It does not say whether they were heard correctly.</div>\n# Dictionary"
    )
    if audit_failures(
        good_section, "Left as dictated",
        "The share of your words the clean-up left exactly as you said them. It does not "
        "say whether they were heard correctly.",
    ):
        print("  ✗ self-test: a known-good fixture was flagged", file=sys.stderr)
        ok = False

    bad_accuracy = 'DICTATIONS = [\n]\n<div class="k">Accuracy</div>\n# Dictionary'
    if not audit_failures(bad_accuracy, "Left as dictated", "anything"):
        print(
            "  ✗ self-test: a restored \"Accuracy\" label was not flagged", file=sys.stderr
        )
        ok = False

    bad_baseline = (
        'DICTATIONS = [\n]\n<div class="k">Left as dictated</div>\n'
        '<span>Baseline</span>\n# Dictionary'
    )
    if not audit_failures(bad_baseline, "Left as dictated", "anything"):
        print(
            "  ✗ self-test: a restored \"Baseline\" meter row was not flagged", file=sys.stderr
        )
        ok = False

    # "Inaccuracy" and "Baselined" are not the retired labels and must not false-positive.
    prefixed = (
        'DICTATIONS = [\n]\n<div class="k">Left as dictated</div>\n'
        '<div class="c">exactly as you said them &mdash; Inaccuracy is Baselined '
        "elsewhere</div>\n# Dictionary"
    )
    if audit_failures(prefixed, "Left as dictated", "exactly as you said them"):
        print(
            "  ✗ self-test: a word merely containing Accuracy/Baseline was flagged",
            file=sys.stderr,
        )
        ok = False

    return ok


def audit():
    failures = audit_pairs()
    if failures:
        print(
            f"\n  ✗ {len(failures)} Dictation artboard contract violation(s):", file=sys.stderr
        )
        for message in failures:
            print(f"    {message}", file=sys.stderr)
        print(
            "    Update Design/_gen_app.py's Dictation rail to match\n"
            "    Sources/UttrflowUX/MainDictationPresentation.swift's DictationPresenter,\n"
            "    then regenerate both Main-Dictation artboards.",
            file=sys.stderr,
        )
        return 1

    print(
        "dictation contract audit: the Dictation rail matches DictationPresenter, "
        "with no Accuracy label or baseline meter.\n"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="prove the extractors resolve a known-good fixture and catch known regressions",
    )
    options = parser.parse_args()

    if options.self_test:
        if not self_test():
            print(
                "\ndictation contract audit: self-test failed; the parser is broken.\n",
                file=sys.stderr,
            )
            return 1
        return 0

    return audit()


if __name__ == "__main__":
    sys.exit(main())
