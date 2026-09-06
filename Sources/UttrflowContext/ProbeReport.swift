import Foundation

/// Renders a sweep as the markdown that goes into `Docs/predict-probe.md`.
public struct ProbeReport: Sendable {
    private let sweep: CapabilitySweep

    public init(_ sweep: CapabilitySweep) {
        self.sweep = sweep
    }

    /// The whole report: the table, then the decision it forces.
    public func markdown() -> String {
        guard !sweep.isEmpty else { return "No fields were read. Focus a text field and probe again.\n" }
        return table() + "\n" + verdict()
    }

    private func table() -> String {
        var lines = [
            "| Application | Role | Field | Value | Caret | Style | Secure | Read | Placement |",
            "|---|---|---|---|---|---|---|--:|---|",
        ]
        for reading in sweep.readings {
            lines.append(
                "| \(escape(reading.application)) | \(escape(reading.role ?? "—")) "
                    + "| \(escape(reading.locator ?? "—")) "
                    + "| \(yesOrNo(reading.reportsValue)) | \(yesOrNo(reading.reportsCaretRect)) "
                    + "| \(yesOrNo(reading.reportsTextStyle)) | \(yesOrNo(reading.isSecure)) "
                    + "| \(reading.readMicroseconds) µs | \(name(reading.placement)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func verdict() -> String {
        let inline = percentage(sweep.inlineShare)
        let eligible = percentage(sweep.eligibleShare)
        let decision =
            sweep.inlineIsWorthBuilding
            ? "The inline ghost reaches enough fields to be worth it; it is the only surface."
            : "The inline ghost reaches too few fields to lead with, and there is no other surface to fall back on."
        return """
            \(sweep.readings.count) fields read. \(eligible) can take a suggestion at all, \
            \(inline) can take the inline ghost \
            (threshold \(percentage(CapabilitySweep.inlineThreshold))).

            \(decision)
            """
    }

    private func percentage(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// One column of the table, as the word a reader scans for.
    private func yesOrNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private func name(_ placement: SuggestionPlacement?) -> String {
        switch placement {
        case .inlineGhost: "inline ghost"
        case .windowStrip: "window strip"
        case nil: "nothing"
        }
    }

    /// Keeps an application name containing a pipe from breaking the table.
    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }
}
