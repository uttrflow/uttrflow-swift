"""Summarises llvm-cov JSON per module and fails below the threshold.

Reads llvm-cov `export -format=text` JSON on stdin. Attributes each source file to
the module that owns it by its path under Sources/<Module>/.

Exclusions are listed here with their reason and printed on every run. A coverage
gate that hides what it skipped reports a number nobody can trust.

The rule an exclusion has to keep — that the file is small enough for reading it to be
a sufficient review — is checked here too, with `--check-exclusions`, because for years
it was only written down: the list had grown to hold a 2,263-line file while still
claiming every entry could be reviewed by reading.
"""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Iterable
from pathlib import Path

THRESHOLD = float(os.environ.get("THRESHOLD", "95"))
PACKAGE_ROOT = Path(os.environ.get("PACKAGE_ROOT", ".")).resolve()
SOURCES_ROOT = PACKAGE_ROOT / "Sources"

EXCLUDED_MODULES = {
    "UttrflowTestSupport": "test scaffolding, never shipped",
    "uttrflow-dev": "developer harness; argument wiring and printing only",
    "uttrflow-eval": "measurement harness; argument wiring and printing only",
    "uttrflow-bakeoff": "measurement harness; argument wiring and printing only",
}

# Files whose behaviour can only be exercised by real hardware or a real user. Each one
# must be small enough that reading it is a sufficient review, which `REVIEWABLE_LINES`
# below is the measure of; an entry over that size is listed in `OVERSIZED_EXCLUSIONS`
# with where its decisions are tested instead.
EXCLUDED_FILES = {
    "UttrflowAudio/AVAudioEngineMicrophoneSource.swift": "drives a physical microphone",
    "UttrflowAudio/RecordingCue+System.swift": "plays a sound out of the speakers",
    "UttrflowPermissions/MicrophonePermissionGate+System.swift": "puts a system dialog on screen",
    "UttrflowPermissions/AccessibilityPermissionGate+System.swift": "opens System Settings",
    "UttrflowPermissions/SystemSettingsOpener+System.swift": "hands a System Settings address to the system to open",
    "UttrflowSettings/LaunchAtLogin+System.swift": "registers a login item with the system",
    "UttrflowContext/MacContextEngine+System.swift": "reads other apps' windows through Accessibility",
    "UttrflowContext/SurfaceProbe+System.swift": "asks other apps about their focused field",
    "UttrflowContext/FocusedFieldReader+System.swift": (
        "reads the focused field of another app through Accessibility; everything decided "
        "from what it reads is FocusedFieldSnapshot, which is tested"
    ),
    "UttrflowContext/CompositionProbe+System.swift": (
        "asks the focused field and the Text Input Sources database about input-method "
        "composition; the rule it feeds is Composition, which is tested"
    ),
    "UttrflowInput/SystemInput.swift": "drives the clipboard, the keyboard and other apps' windows",
    "UttrflowAccount/BackendTransport+URLSession.swift": (
        "the one place this app opens a socket; every decision worth getting wrong is in "
        "the request handed to it, and those are tested against a stub transport"
    ),
    "UttrflowAccount/TokenStore+Keychain.swift": (
        "reads and writes the login keychain, which a test cannot touch without prompting "
        "whoever is running it"
    ),
    "UttrflowAccount/DeviceIdentity+System.swift": "reads this Mac's name from the system",
    "UttrflowAccount/LoopbackListener+System.swift": (
        "binds a TCP port and speaks HTTP to a browser; what it decides — parsing the request "
        "line, whether a callback answers this attempt, and the page it answers with — is "
        "tested directly, and LoopbackListenerTests drives the real port"
    ),
    "UttrflowInput/CarbonHotkeyMonitor.swift": "registers a system-wide hotkey with Carbon",
    "UttrflowInput/KeyInterceptor.swift": (
        "creates a CGEventTap, which needs Accessibility and a window server; every rule "
        "it holds — which keys are armed, and what each one means — is KeyRouting, which "
        "is tested"
    ),
    "UttrflowInput/SystemKeyboard.swift": (
        "creates the one CGEventTap, which needs Accessibility and a window server; the two "
        "rules it holds are tested without it — HotkeyRecogniser against every shape of "
        "binding, and TapDisableWindow against a tap the system keeps switching off"
    ),
    "UttrflowClipboard/CodeFormatting+System.swift": "spawns another program and pipes bytes through it",
    "UttrflowPredict/EnvironmentReading+System.swift": (
        "runs git, reads directories and scans PATH; what is done with the answers — which "
        "kinds are asked for, what finishes the line, and how long an answer is believed — is "
        "decided in EnvironmentSource and tested there against a substitute machine"
    ),
    "Uttrflow/UttrflowApp.swift": "the process entry point",
    "Uttrflow/AppDelegate.swift": (
        "assembles the real engines, windows and permission gates; the intents that "
        "change stored data are driven against a sandbox in MainIntentWiringTests, the "
        "rest are not"
    ),
    "Uttrflow/Updates/UpdateController.swift": (
        "owns Sparkle's updater and the one socket outside UttrflowAccount; it holds no rule "
        "of its own — when an update may install is UpdateGate, and which feed may be read is "
        "UpdateFeed, both tested"
    ),
    "Uttrflow/Onboarding/OnboardingAccountLayer.swift": "wiring only; pairs the backend with the store that believes its key",
    "Uttrflow/Onboarding/NetworkReachability+System.swift": "watches the real network path",
    "Uttrflow/Onboarding/OnboardingView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Onboarding/OnboardingRail.swift": "SwiftUI; the step list it draws is tested in OnboardingStepTests",
    "Uttrflow/Onboarding/OnboardingWindowController.swift": "owns an on-screen window and the real permission gates",
    "Uttrflow/Settings/SettingsWindowController.swift": "owns an on-screen window",
    "Uttrflow/Settings/SettingsViewModel.swift": "observable shell; every decision is in SettingsSession",
    "Uttrflow/Settings/SettingsRootView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Settings/SettingsPaneView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Settings/SettingsControlView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Settings/SettingsControlStyles.swift": "SwiftUI; appearance only, and every control it restyles keeps the behaviour the platform gives it",
    "Uttrflow/Settings/SettingsCapabilities+System.swift": "reads what this Mac can do from the system",
    "Uttrflow/Settings/ApplicationPicker+System.swift": "asks the user to pick an application through a system menu and open panel",
    "Uttrflow/Main/MainWindowController.swift": "owns an on-screen window",
    "Uttrflow/Brand/UttrflowMarkView.swift": (
        "SwiftUI; the geometry it draws is UttrflowMark, which is tested"
    ),
    "Uttrflow/Sidebar/SidebarView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/HomePageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/ClipboardDemonstration.swift": (
        "SwiftUI; what it decides is in ClipboardDemonstrationPhase, which says what is drawn "
        "at an instant, ClipboardDemonstrationMoments, which says when to wake, and "
        "ClipboardDemonstrationMetrics, which chooses the arrangement from a width, all tested"
    ),
    "Uttrflow/Main/WindowVisibility.swift": (
        "reads a real NSWindow and NSApp for the facts WindowAttention decides from, which is "
        "tested; nothing here a test could reach without a window server"
    ),
    "Uttrflow/Main/OrbitStage.swift": "SwiftUI, drawn from a tested presentation and a tested ring",
    "Uttrflow/Main/ApplicationIconSource+System.swift": "asks the system for another app's icon",
    "Uttrflow/Panel/PanelThumbnailSource+System.swift": "decodes a picture off the disk",
    "Uttrflow/Main/OrbitPalette.swift": "colour values; the two decidable parts are tested in OrbitPaletteTests",
    "Uttrflow/Main/DictationPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/DictionaryPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/CorrectionsPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/InsightsPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/SnippetsPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/StylePageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/AccountPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/AvatarView.swift": "SwiftUI; which of the two things it draws is decided in AccountPagePresentation",
    "Uttrflow/Main/MainWindowView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/MainPieces.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/HistoryPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/DiagnosticsPageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Dock/DockPanelController.swift": "owns an on-screen floating window",
    "Uttrflow/Suggestion/SuggestionCoordinator.swift": (
        "wiring only: an event tap, a global key monitor and another app's focused field, "
        "none of which a headless test has; every rule it sequences is SuggestionSession, "
        "every field reading it maps goes through SuggestionMoment, and whether the model is asked, "
        "reused, skipped, drawn fresh or asked for alternatives is ModelPass, all of which are tested"
    ),
    "Uttrflow/Suggestion/SuggestionPanelController.swift": (
        "owns an on-screen floating window; where it puts it is SuggestionGeometry and "
        "what it draws is SuggestionPresentation, both of which are tested"
    ),
    "Uttrflow/Suggestion/SuggestionView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Panel/QuickPanelController.swift": "owns an on-screen floating window",
    "Uttrflow/Panel/QuickPanelView.swift": (
        "SwiftUI, drawn from a tested presentation, apart from the ⌘-chord and Escape handling "
        "it decides itself, which #630 moves into a pure type in UttrflowUX"
    ),
    "Uttrflow/Dock/DockView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/MenuBar/MenuBarController.swift": "owns a menu bar item",
    "UttrflowSpeech/TokenizerDownload.swift": "fetches the tokenizer over the real network at install time",
    "UttrflowSpeech/WhisperKitBackend.swift": "loads a downloaded model and decodes real speech",
    "UttrflowSpeech/AppleSpeechBackend.swift": "drives the system recogniser on real speech",
    "UttrflowAI/AppleFoundationCleanupModel.swift": "runs Apple's on-device language model",
    "UttrflowLocalModel/MLXCleanupModel.swift": "downloads gigabytes and runs GPU inference",
    "UttrflowLocalModel/AppleCandidateGenerator.swift": "runs Apple's on-device model, which only the real system can",
    "UttrflowLocalModel/TokenHealing+Model.swift": (
        "reads the loaded model's vocabulary and masks its Metal logits; the rule it applies is "
        "TokenHealing, tested byte by byte without a model"
    ),
    "UttrflowLocalModel/QuantizedLoad.swift": (
        "builds a model's layers on MLX and loads gigabytes of weights; which layers it builds quantized "
        "is QuantizedLayerPlan, tested against safetensors headers"
    ),
    "UttrflowLocalModel/MLXCandidateScorer.swift": (
        "loads a model and runs GPU inference; the text its answers are read through is "
        "CompletionText, and what is done with a score is Verification and Verifier, all tested"
    ),
}

# The most lines an excluded file may have for reading it to be a sufficient review. Past
# this a reviewer skims, so the exclusion rests on nobody's judgement. Chosen to leave the
# entries below and nothing else over the line, so the check starts green and ratchets down.
REVIEWABLE_LINES = 400

# The excluded files over that size, each with what carries the review instead of reading.
# Listed rather than waived so the check cannot grow quietly: a file that arrives over the
# limit fails until its decisions are tested or it is added here with a reason, and an entry
# whose file has come back under the limit fails too, so the list only shrinks.
OVERSIZED_EXCLUSIONS = {
    "Uttrflow/AppDelegate.swift": (
        "nothing covers the assembly beyond the intents in MainIntentWiringTests; #145 holds the "
        "app target's test gap and #661 the split that would let the rest be tested"
    ),
    "Uttrflow/Panel/QuickPanelView.swift": (
        "the ⌘-chord and Escape handling in it has no test at all; #630 moves it into UttrflowUX"
    ),
    "Uttrflow/Suggestion/SuggestionCoordinator.swift": (
        "the two rules it keeps are tested in SuggestionReadGateTests and SuggestionDebounceTests, "
        "and its model-pass decisions in ModelPassTests; still untested is the capture-consent "
        "and tap-insertion sequencing"
    ),
    "Uttrflow/Dock/DockView.swift": "what DockViewModel decides is tested in DockClockTests and DockBarsTests",
    "Uttrflow/Onboarding/OnboardingView.swift": (
        "OnboardingModel forwards every press to OnboardingFlow, which OnboardingFlowTests drives"
    ),
    "Uttrflow/Main/MainPieces.swift": (
        "views, metrics and colour mappings; the one rule among them is RowReveal, tested in RowRevealTests"
    ),
    "UttrflowLocalModel/MLXCandidateScorer.swift": (
        "CompletionText holds the text rules its answers are read through, and is tested without MLX"
    ),
    "UttrflowContext/FocusedFieldReader+System.swift": (
        "FocusedFieldSnapshot holds everything decided from what it reads, and is tested"
    ),
}


def relative(path: str) -> Path | None:
    try:
        return Path(path).resolve().relative_to(SOURCES_ROOT)
    except ValueError:
        return None


def line_counts(sources_root: Path, excluded: Iterable[str] = EXCLUDED_FILES) -> dict[str, int | None]:
    """Lines in each excluded file, or None where the entry names a file that is not there."""
    counts: dict[str, int | None] = {}
    for path in excluded:
        file = sources_root / path
        counts[path] = (
            len(file.read_text(encoding="utf-8").splitlines()) if file.is_file() else None
        )
    return counts


def exclusion_problems(
    counts: dict[str, int | None],
    oversized: dict[str, str] = OVERSIZED_EXCLUSIONS,
    limit: int = REVIEWABLE_LINES,
) -> list[str]:
    """Says where the exclusion list has stopped describing the tree, one sentence per problem."""
    problems = []
    for path in sorted(counts):
        lines = counts[path]
        if lines is None:
            problems.append(f"{path} is excluded but is not in the tree; delete the entry")
            continue
        if lines > limit and path not in oversized:
            problems.append(
                f"{path} is {lines} lines, past the {limit} that reading it as a review is worth: "
                "test what it decides and drop the exclusion, or list it in OVERSIZED_EXCLUSIONS "
                "with what reviews it instead"
            )
        if lines > limit and not oversized.get(path, "x").strip():
            problems.append(
                f"{path} is listed as oversized with no reason; say what reviews it instead, "
                "since an exclusion nobody can read is the silence this list exists to break"
            )
        if lines <= limit and path in oversized:
            problems.append(
                f"{path} is {lines} lines, back inside the {limit}-line limit; "
                "delete its OVERSIZED_EXCLUSIONS entry, which now excuses nothing"
            )
    for path in sorted(set(oversized) - set(counts)):
        problems.append(f"{path} is listed as oversized but is not excluded; delete the entry")
    return problems


def self_test() -> int:
    """Proves each exclusion check fails on the state it is there to catch."""
    print("\nSelf-test: each check must fail on the state it polices")
    cases = (
        ("an excluded file that has grown past the limit", {"A.swift": 401}, {}, "past the 400"),
        ("an exclusion whose file is gone", {"A.swift": None}, {}, "not in the tree"),
        ("an oversized entry with a blank reason", {"A.swift": 401}, {"A.swift": " "}, "no reason"),
        ("an oversized entry whose file has shrunk", {"A.swift": 400}, {"A.swift": "why"}, "back inside"),
        ("an oversized entry for a file nobody excludes", {}, {"B.swift": "why"}, "is not excluded"),
    )
    failed = 0
    for description, counts, oversized, expected in cases:
        problems = exclusion_problems(counts, oversized=oversized)
        if any(expected in problem for problem in problems):
            print(f"  ✓ {description}")
        else:
            print(f"  ✗ {description}: the check no longer fails on it")
            failed += 1
    within = exclusion_problems({"A.swift": 400}, oversized={})
    if within:
        print(f"  ✗ a file inside the limit was reported: {within[0]}")
        failed += 1
    else:
        print("  ✓ a file inside the limit passes")
    return failed


def report_exclusions(counts: dict[str, int | None], problems: list[str]) -> None:
    """Prints the size of every exclusion, because a limit nobody sees is the one that drifted."""
    print(f"\nExclusion sizes (limit {REVIEWABLE_LINES} lines, past which reading is not a review)")
    print("-" * 52)
    for path in sorted(counts, key=lambda path: -(counts[path] or 0)):
        lines = counts[path]
        if lines is None:
            print(f"  MISSING  {path}")
            continue
        note = f"  over: {OVERSIZED_EXCLUSIONS[path]}" if path in OVERSIZED_EXCLUSIONS else ""
        print(f"  {lines:>5}  {path}{note}")
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)


def main() -> int:
    counts = line_counts(SOURCES_ROOT)
    problems = exclusion_problems(counts)
    # Reads no coverage report, so it runs ahead of the build rather than after the tests.
    if "--check-exclusions" in sys.argv[1:]:
        report_exclusions(counts, problems)
        if problems:
            return 1
        oversized = sum(1 for path in counts if path in OVERSIZED_EXCLUSIONS)
        print(
            f"\ncoverage exclusions: {len(counts)} files, all present, "
            f"{oversized} over the limit and each saying what reviews it instead."
        )
        if "--self-test" in sys.argv[1:] and self_test():
            print("\n  ✗ a check no longer fails on the state it polices\n", file=sys.stderr)
            return 1
        print()
        return 0

    report = json.load(sys.stdin)
    totals: dict[str, list[int]] = {}
    skipped_files: list[str] = []

    for export in report.get("data", []):
        for file_entry in export.get("files", []):
            path = relative(file_entry.get("filename", ""))
            if path is None or not path.parts:
                continue
            module = path.parts[0]
            if module in EXCLUDED_MODULES:
                continue
            if path.as_posix() in EXCLUDED_FILES:
                skipped_files.append(path.as_posix())
                continue
            lines = file_entry.get("summary", {}).get("lines", {})
            covered, count = totals.setdefault(module, [0, 0])
            totals[module] = [covered + lines.get("covered", 0), count + lines.get("count", 0)]

    if not totals:
        print("error: no product modules found in the coverage report", file=sys.stderr)
        return 1

    failures = []
    print(f"\nLine coverage (floor {THRESHOLD:.0f}%)")
    print("-" * 52)
    for module in sorted(totals):
        covered, count = totals[module]
        percent = 100.0 * covered / count if count else 100.0
        status = "PASS" if percent >= THRESHOLD else "FAIL"
        if status == "FAIL":
            failures.append((module, percent))
        print(f"  {status}  {module:<28} {percent:6.2f}%  ({covered}/{count})")

    grand_covered = sum(v[0] for v in totals.values())
    grand_count = sum(v[1] for v in totals.values())
    grand = 100.0 * grand_covered / grand_count if grand_count else 100.0
    print("-" * 52)
    print(f"        {'TOTAL':<28} {grand:6.2f}%  ({grand_covered}/{grand_count})")

    print("\nNot measured")
    for module, reason in sorted(EXCLUDED_MODULES.items()):
        print(f"  {module:<34}        {reason}")
    for path, reason in sorted(EXCLUDED_FILES.items()):
        seen = "" if path in skipped_files else "  [not found in report]"
        lines = counts[path]
        size = f"{lines:>5}L" if lines is not None else "    ?L"
        print(f"  {path:<34} {size}  {reason}{seen}")
    print()

    for module, percent in failures:
        print(f"error: {module} is at {percent:.2f}%, below the {THRESHOLD:.0f}% floor", file=sys.stderr)
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main())
