// Checks formatting sheet reuse without presenting native controls.
import Testing
import UttrflowClipboard
@testable import UttrflowUX

@Suite("Formatting sheet source storage")
struct FormattingSheetMemoTests {
    private func comparisons(_ work: () -> Void) -> Int {
        let tally = DiffTally()
        TextDiff.$tally.withValue(tally) { work() }
        return tally.count
    }

    @Test("remembering a prepared pair replaces the previous pair without another comparison")
    func preparedReplacement() {
        let memo = FormattingSheetMemo()
        let original = "func a(){let x=1}"
        let first = "func a() { let x = 1 }"
        let second = "func a() {\n    let x = 1\n}"
        let firstSheet = memo.sheet(from: original, to: first)
        let prepared = PreparedFormattingSheet(from: original, to: second)
        memo.remember(prepared)
        let hit = comparisons {
            #expect(memo.sheet(from: original, to: second) == prepared.sheet)
        }
        #expect(hit == 0)
        let control = comparisons { _ = FormattingSheetMemo().sheet(from: original, to: first) }
        let replacement = comparisons { #expect(memo.sheet(from: original, to: first) == firstSheet) }
        #expect(replacement == control)
    }

    @Test("each recorded source field invalidates the single remembered sheet")
    func sourceFields() {
        func check(_ original: String, _ formatted: String, _ title: String, _ confirmTitle: String) {
            let memo = FormattingSheetMemo()
            _ = memo.sheet(from: "let x=1", to: "let x = 1")
            let fresh = FormattingSheetMemo()
            var expected: PanelSheetPresentation?
            let control = comparisons {
                expected = fresh.sheet(
                    from: original, to: formatted, title: title, confirmTitle: confirmTitle)
            }
            let miss = comparisons {
                #expect(
                    memo.sheet(from: original, to: formatted, title: title, confirmTitle: confirmTitle)
                        == expected)
            }
            #expect(miss == control)
            let hit = comparisons {
                #expect(
                    memo.sheet(from: original, to: formatted, title: title, confirmTitle: confirmTitle)
                        == expected)
            }
            #expect(hit == 0)
        }
        check("let x=2", "let x = 1", "Format this code?", "Keep it")
        check("let x=1", "let x = 2", "Format this code?", "Keep it")
        check("let x=1", "let x = 1", "Review formatting", "Keep it")
        check("let x=1", "let x = 1", "Format this code?", "Apply formatting")
    }
}
