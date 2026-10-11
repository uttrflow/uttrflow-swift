import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("Panel row contexts stay attached to their answers", OwnPanelCache())
struct PanelRowContextTests {
    @Test("a late row cannot replace another context's row")
    func lateRow() {
        let fixture = Fixture()
        let memo = PanelRowMemo()
        let first = memo.row(for: fixture.key, in: fixture.availableContext) {
            #expect(
                memo.row(for: fixture.key, in: fixture.missingContext) { fixture.missingRow }
                    == fixture.missingRow)
            return fixture.availableRow
        }

        #expect(first == fixture.availableRow)
        #expect(
            memo.row(for: fixture.key, in: fixture.missingContext) { fixture.missingRow }
                == fixture.missingRow)
        #expect(memo.builds == 2)
    }

    @Test("a completed list cannot relabel another context's individual rows")
    func lateList() {
        let fixture = Fixture()
        let memo = PanelRowMemo()
        let listID = UUID()
        let other = Fixture()
        let rows = memo.rows(listID: listID, results: [fixture.result], context: fixture.availableContext) {
            _ in
            #expect(
                memo.rows(listID: listID, results: [other.result], context: other.missingContext) { _ in
                    other.missingRow
                } == [other.missingRow])
            return fixture.availableRow
        }

        #expect(rows == [fixture.availableRow])
        #expect(
            memo.row(for: other.key, in: other.availableContext) { other.availableRow } == other.availableRow)
        #expect(
            memo.rows(listID: listID, results: [fixture.result], context: fixture.missingContext) { _ in
                fixture.missingRow
            } == [fixture.missingRow])
        #expect(
            memo.row(for: fixture.key, in: fixture.availableContext) { fixture.availableRow }
                == fixture.availableRow)
    }

    @Test("an individual row context does not relabel the cached whole list")
    func listAfterRow() {
        let fixture = Fixture()
        let memo = PanelRowMemo()
        let listID = UUID()
        _ = memo.rows(listID: listID, results: [fixture.result], context: fixture.availableContext) { _ in
            fixture.availableRow
        }
        #expect(
            memo.row(for: fixture.key, in: fixture.missingContext) { fixture.missingRow }
                == fixture.missingRow)

        #expect(
            memo.rows(listID: listID, results: [fixture.result], context: fixture.missingContext) { _ in
                fixture.missingRow
            } == [fixture.missingRow])
    }

    @Test("grouped rows with one list identity still belong to their context")
    func lateGroups() {
        let fixture = Fixture()
        let memo = PanelRowMemo()
        let listID = UUID()
        let available = fixture.groups(fixture.availableRow)
        let missing = fixture.groups(fixture.missingRow)
        _ = memo.rows(listID: listID, results: [fixture.result], context: fixture.availableContext) { _ in
            fixture.availableRow
        }
        let groups = memo.groups(for: listID, in: fixture.availableContext) {
            _ = memo.rows(listID: listID, results: [fixture.result], context: fixture.missingContext) { _ in
                fixture.missingRow
            }
            #expect(memo.groups(for: listID, in: fixture.missingContext) { missing } == missing)
            return available
        }

        #expect(groups == available)
        #expect(memo.groups(for: listID, in: fixture.missingContext) { missing } == missing)
        #expect(memo.groupBuilds == 3)
    }

    private struct Fixture {
        let result: PanelResult
        let availableRow: PanelRow
        let missingRow: PanelRow
        let availableContext: PanelRowMemo.Context
        let missingContext: PanelRowMemo.Context

        init() {
            let clip = Clip(
                text: "notes.txt", kind: .file, copiedAt: PanelFixture.now,
                files: [ClipFileReference(path: "/tmp/uttrflow-context/notes.txt")])
            result = PanelResult(clip: clip, match: .content, isExactAlias: false)
            let available = PanelFixture.panel([clip], query: "notes")
            var missing = available
            missing.missingFiles = [clip.id: ["notes.txt"]]
            availableRow = PanelPresenter.row(for: result, in: available, isSelected: false)
            missingRow = PanelPresenter.row(for: result, in: missing, isSelected: false)
            availableContext = Self.context(available)
            missingContext = Self.context(missing)
        }

        var key: PanelRowMemo.Key { .init(result: result, isMasked: false, isGone: false) }

        func groups(_ row: PanelRow) -> [PanelResultGroup] {
            [PanelResultGroup(field: .content, title: "Contents", rows: [row], more: 0)]
        }

        private static func context(_ snapshot: PanelSnapshot) -> PanelRowMemo.Context {
            .init(
                needle: snapshot.needle, locale: snapshot.locale, now: snapshot.now,
                imagesFolder: snapshot.imagesFolder, formattableLanguages: snapshot.formattableLanguages,
                revealed: snapshot.revealed, missingImages: snapshot.missingImages,
                missingFiles: snapshot.missingFiles)
        }
    }
}
