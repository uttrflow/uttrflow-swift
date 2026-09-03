"""Summarises llvm-cov JSON per module and fails below the threshold.

Reads llvm-cov `export -format=text` JSON on stdin. Attributes each source file to
the module that owns it by its path under Sources/<Module>/.

Exclusions are listed here with their reason and printed on every run. A coverage
gate that hides what it skipped reports a number nobody can trust.
"""

from __future__ import annotations

import json
import os
import sys
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

# Files whose behaviour can only be exercised by real hardware or a real user. Each
# one must be small enough that reading it is a sufficient review.
EXCLUDED_FILES = {
    "UttrflowAudio/AVAudioEngineMicrophoneSource.swift": "drives a physical microphone",
    "UttrflowAudio/RecordingCue+System.swift": "plays a sound out of the speakers",
    "UttrflowPermissions/MicrophonePermissionGate+System.swift": "puts a system dialog on screen",
    "UttrflowPermissions/AccessibilityPermissionGate+System.swift": "opens System Settings",
    "UttrflowSettings/LaunchAtLogin+System.swift": "registers a login item with the system",
    "UttrflowContext/MacContextEngine+System.swift": "reads other apps' windows through Accessibility",
    "UttrflowContext/SurfaceProbe+System.swift": "asks other apps about their focused field",
    "UttrflowPredictCapture/FieldReader+System.swift": "asks other apps what their focused field is called",
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
        "binds a TCP port and speaks HTTP to a browser; the two parts that decide anything "
        "— parsing the request line and the page it answers with — are tested directly"
    ),
    "UttrflowInput/CarbonHotkeyMonitor.swift": "registers a system-wide hotkey with Carbon",
    "UttrflowInput/HeldModifierMonitor.swift": (
        "watches NSEvent's global and local flag monitors, which need a window server; "
        "the two rules it used to hold are HeldModifierEdge, which is tested"
    ),
    "UttrflowInput/ActivationMonitor.swift": (
        "picks one of the two monitors above and forwards its stream; both are excluded "
        "for needing a window server, so there is nothing here a test could reach"
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
        "owns Sparkle's updater and the one socket outside UttrflowAccount; the only rule "
        "it holds — when an update may install — is UpdateGate, which is tested"
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
    "Uttrflow/Main/MainWindowController.swift": "owns an on-screen window",
    "Uttrflow/Brand/UttrflowMarkView.swift": (
        "SwiftUI; the geometry it draws is UttrflowMark, which is tested"
    ),
    "Uttrflow/Sidebar/SidebarView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/HomePageView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Main/WindowVisibility.swift": (
        "asks a real NSWindow whether it is on screen; there is nothing to decide "
        "here that a test could reach without a window server"
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
    "Uttrflow/Panel/QuickPanelController.swift": "owns an on-screen floating window",
    "Uttrflow/Panel/QuickPanelView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/Dock/DockView.swift": "SwiftUI, drawn from a tested presentation",
    "Uttrflow/MenuBar/MenuBarController.swift": "owns a menu bar item",
    "UttrflowSpeech/TokenizerDownload.swift": "fetches the tokenizer over the real network at install time",
    "UttrflowSpeech/WhisperKitBackend.swift": "loads a downloaded model and decodes real speech",
    "UttrflowSpeech/AppleSpeechBackend.swift": "drives the system recogniser on real speech",
    "UttrflowAI/AppleFoundationCleanupModel.swift": "runs Apple's on-device language model",
    "UttrflowLocalModel/MLXCleanupModel.swift": "downloads gigabytes and runs GPU inference",
}


def relative(path: str) -> Path | None:
    try:
        return Path(path).resolve().relative_to(SOURCES_ROOT)
    except ValueError:
        return None


def main() -> int:
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
        print(f"  {module:<34} {reason}")
    for path, reason in sorted(EXCLUDED_FILES.items()):
        seen = "" if path in skipped_files else "  [not found in report]"
        print(f"  {path:<34} {reason}{seen}")
    print()

    for module, percent in failures:
        print(f"error: {module} is at {percent:.2f}%, below the {THRESHOLD:.0f}% floor", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
