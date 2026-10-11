import AppKit
import Foundation
import SwiftUI
import Testing
import UttrflowCore
import UttrflowHistory

@testable import Uttrflow

@MainActor
@Suite("Report this dictation sheet")
struct DictationReportSheetTests {
    private func report() -> DictationReport {
        DictationReport(
            record: DictationRecord(
                text: "Meet at the station", when: Date(timeIntervalSince1970: 1_700_000_000),
                applicationIdentifier: "com.example.notes", cleanedBy: .rules))
    }

    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("report-\(UUID().uuidString).txt")
    }

    @Test("the draft holds the report the preview edits")
    func draftHoldsTheReport() {
        let draft = DictationReportDraft(report())
        draft.report.removeLine(at: 0)
        #expect(draft.report.lines.first == "Audio: never included")
    }

    @Test("the preview draws one field per line of the report")
    func previewDrawsEveryLine() {
        let draft = DictationReportDraft(report())
        let host = NSHostingView(rootView: DictationReportPreview(draft: draft))
        host.frame = NSRect(x: 0, y: 0, width: 464, height: 224)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width > 0)
        #expect(draft.report.lines.count == 7)
    }

    @Test("Copy hands the draft's text to the clipboard")
    func copyHandsOverTheText() {
        var copied: String?
        var shown: NSAlert?
        DictationReportSheet.present(
            report(),
            copy: {
                copied = $0
                return true
            },
            run: {
                shown = $0
                return .alertFirstButtonReturn
            })
        #expect(copied == report().text)
        #expect(shown?.messageText == "Report This Dictation")
        #expect(shown?.buttons.map(\.title) == ["Copy", "Save…", "Cancel"])
        #expect(shown?.accessoryView is NSHostingView<DictationReportPreview>)
    }

    @Test("Save hands the draft to the save step and copies nothing")
    func saveHandsOverTheReport() {
        var saved: DictationReport?
        var copied = false
        DictationReportSheet.present(
            report(),
            copy: { _ in
                copied = true; return true
            },
            run: { _ in .alertSecondButtonReturn }, save: { saved = $0 })
        #expect(saved == report())
        #expect(!copied)
    }

    @Test("Cancel copies and saves nothing")
    func cancelDoesNothing() {
        var touched = false
        DictationReportSheet.present(
            report(),
            copy: { _ in
                touched = true; return true
            },
            run: { _ in .alertThirdButtonReturn }, save: { _ in touched = true })
        #expect(!touched)
    }

    @Test("saving writes the report's bytes to the chosen file")
    func savingWritesTheFile() throws {
        let destination = scratchFile()
        defer { try? FileManager.default.removeItem(at: destination) }
        var offered: NSSavePanel?
        DictationReportSheet.save(
            report(),
            choose: {
                offered = $0
                return destination
            }, fail: { _ in Issue.record("a write that worked was reported as failed") })
        #expect(try Data(contentsOf: destination) == report().bytes)
        #expect(offered?.nameFieldStringValue == "Uttrflow-Dictation-Report.txt")
        #expect(offered?.canCreateDirectories == true)
    }

    @Test("a panel dismissed without a file writes nothing")
    func dismissedPanelWritesNothing() {
        DictationReportSheet.save(
            report(), choose: { _ in nil },
            fail: { _ in Issue.record("a dismissed panel was reported as a failed write") })
    }

    @Test("a file that cannot be written is reported, not dropped")
    func unwritableFileIsReported() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("absent-\(UUID().uuidString)/report.txt")
        var failure: NSAlert?
        DictationReportSheet.save(report(), choose: { _ in missing }, fail: { failure = $0 })
        #expect(failure?.messageText == "Report could not be saved")
    }
}
