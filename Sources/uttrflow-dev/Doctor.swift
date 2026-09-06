// The `doctor` command: checks permissions and setup.
import ArgumentParser
private import AVFoundation
private import Foundation
private import UttrflowCore
private import UttrflowInput
private import UttrflowPermissions

/// Reports whether this Mac can actually do what the pipeline needs.
struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check permissions and audio hardware."
    )

    func run() async throws {
        print("Uttrflow environment\n")

        let status = await MicrophonePermissionGate().status()
        print("  Microphone permission   \(describe(status))")

        // Nothing focused and a focused field that hides its selection look identical from outside.
        let accessibility = await AccessibilityPermissionGate().status()
        print("  Accessibility           \(describe(accessibility))")
        let focus = AXAccessibilityFocus()
        print("  Something focused       \(focus.hasFocusedElement() ? "yes" : "no")")
        print(
            "  Reports its selection   "
                + (focus.focusedTextField() != nil
                    ? "yes — text can be written straight in"
                    : "no — a paste is the best that can be done here)"))

        let engine = AVAudioEngine()
        let format = engine.inputNode.inputFormat(forBus: 0)
        if format.sampleRate > 0 {
            print("  Input device            present")
            print(
                "  Input format            \(Int(format.sampleRate)) Hz, "
                    + "\(format.channelCount) channel\(format.channelCount == 1 ? "" : "s")")
            print(
                "  Converts to canonical   "
                    + "\(AudioSamples.canonicalSampleRate) Hz mono, 1 channel")
        } else {
            print("  Input device            none found")
        }

        if status != .granted {
            print("\nRun `uttrflow-dev record` to trigger the permission prompt.")
        }
    }

    private func describe(_ status: PermissionStatus) -> String {
        switch status {
        case .granted: "granted"
        case .denied: "denied — turn it on in System Settings › Privacy & Security › Microphone"
        case .restricted: "blocked by device policy"
        case .notDetermined: "not asked yet"
        }
    }
}
