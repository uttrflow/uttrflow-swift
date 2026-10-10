// The "Report this dictation" preview: every line the report shares, editable, ready to copy or save.

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UttrflowCore
import UttrflowHistory

/// Holds the report while the person edits it, so Copy and Save read the same lines the preview shows.
@MainActor
@Observable
final class DictationReportDraft {
    var report: DictationReport

    init(_ report: DictationReport) {
        self.report = report
    }
}

/// The report's lines as fields, each one editable and removable.
struct DictationReportPreview: View {
    @Bindable var draft: DictationReportDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(draft.report.lines.enumerated()), id: \.offset) { index, line in
                    HStack(spacing: 6) {
                        TextField(
                            "Line \(index + 1)",
                            text: Binding(
                                get: { line },
                                set: { draft.report.replaceLine(at: index, with: $0) })
                        )
                        .font(.system(size: 11.5, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        Button {
                            draft.report.removeLine(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(
                            String(localized: "Remove this line", comment: "Remove-line tooltip")
                        )
                        .accessibilityLabel(
                            String(localized: "Remove line \(index + 1)", comment: "Remove-line label")
                        )
                    }
                }
            }
            .padding(2)
        }
        .frame(width: 460, height: 220)
    }
}

/// Shows the preview in a standard alert; Copy and Save take the draft as it stands.
@MainActor
enum DictationReportSheet {
    /// Presents `report`; `copy` puts text on the clipboard and says whether it could.
    static func present(_ report: DictationReport, copy: (String) -> Bool) {
        let draft = DictationReportDraft(report)
        let alert = NSAlert()
        alert.messageText = "Report This Dictation"
        alert.informativeText =
            "Personal details are masked. Edit or remove any line; what you see is exactly what is copied or saved. Nothing is sent, and audio is never included."
        let preview = NSHostingView(rootView: DictationReportPreview(draft: draft))
        preview.frame = NSRect(x: 0, y: 0, width: 464, height: 224)
        alert.accessoryView = preview
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            _ = copy(draft.report.text)
        case .alertSecondButtonReturn:
            save(draft.report)
        default:
            return
        }
    }

    private static func save(_ report: DictationReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Uttrflow-Dictation-Report.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try PrivateFile.writeOwnerOnlyAtomically(report.bytes, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Report could not be saved"
            failure.informativeText = "Uttrflow could not write the selected file."
            failure.runModal()
        }
    }
}
