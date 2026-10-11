import Testing
import UttrflowEval

struct MidWordCalibrationTests {
    private typealias Calibration = MidWordCalibration

    @Test func theSetCoversAFewDozenPrefixesAcrossSeveralTools() {
        #expect(Calibration.all.count >= 36)
        #expect(Set(Calibration.all.map(\.tool)).count >= 12)
        #expect(Calibration.all.allSatisfy { !$0.sensible.isEmpty && !$0.nonsense.isEmpty })
    }

    @Test func everyPrefixIsCutInsideAWordOfEveryLineItIsGiven() {
        let offenders = Calibration.all.filter { !$0.isCutMidWord }.map(\.typed)
        #expect(offenders.isEmpty, "\(offenders)")
    }

    @Test func noPrefixIsDuplicatedAndNoLineIsBothSensibleAndNonsense() {
        let typed = Calibration.all.map(\.typed)
        #expect(Set(typed).count == typed.count)
        #expect(Calibration.all.allSatisfy { Set($0.sensible).isDisjoint(with: $0.nonsense) })
    }

    @Test func nothingInTheSetNamesAPersonalPathOrAUrl() {
        let text = Calibration.all.flatMap { [$0.typed] + $0.sensible + $0.nonsense }
        #expect(text.allSatisfy { !$0.contains("/Users") && !$0.contains("/home") && !$0.contains("@ ") })
        #expect(text.allSatisfy { !$0.contains("://") })
    }

    @Test func aFloorKeepsTheSensibleLinesAtOrAboveItAndPassesTheNonsenseOnes() {
        let scored = [
            Calibration.Scored(typed: "gi", line: "git status", isSensible: true, score: -2.8),
            Calibration.Scored(typed: "gi", line: "git stash", isSensible: true, score: -6.5),
            Calibration.Scored(typed: "gi", line: "gizmo --frobnicate", isSensible: false, score: -5.8),
            Calibration.Scored(typed: "do", line: "dozzle --quantum", isSensible: false, score: -8),
        ]
        let loose = Calibration.tally(scored, floor: -6)
        #expect(loose.sensibleKept == 1 && loose.sensibleTotal == 2)
        #expect(loose.nonsensePassed == 1 && loose.nonsenseTotal == 2)
        let tight = Calibration.tally(scored, floor: -3)
        #expect(tight.sensibleKept == 1 && tight.nonsensePassed == 0)
        #expect(Calibration.tally(scored, floor: -6.5).sensibleKept == 2)
    }

    @Test func aLineWithNoScoreOrANonFiniteOneNeverClearsAFloor() {
        let scored = [
            Calibration.Scored(typed: "gi", line: "git status", isSensible: true, score: nil),
            Calibration.Scored(typed: "gi", line: "git stash", isSensible: true, score: .infinity),
            Calibration.Scored(typed: "gi", line: "gizmo", isSensible: false, score: -.infinity),
        ]
        let result = Calibration.tally(scored, floor: -100)
        #expect(result.unscored == 1)
        #expect(result.sensibleTotal == 1 && result.sensibleKept == 0)
        #expect(result.nonsenseTotal == 1 && result.nonsensePassed == 0)
    }

    @Test func linesComeLabelledAndUnscoredInProbeOrder() {
        let probe = Calibration.Probe("gi", sensible: ["git status"], nonsense: ["gizmo --frobnicate"])
        let lines = Calibration.lines(of: [probe])
        #expect(lines.map(\.line) == ["git status", "gizmo --frobnicate"])
        #expect(lines.map(\.isSensible) == [true, false])
        #expect(lines.allSatisfy { $0.score == nil })
        #expect(probe.tool == "gi")
    }

    @Test func aPrefixEndingOnASpaceOrAWholeLineIsNotMidWord() {
        #expect(!Calibration.Probe("git ", sensible: ["git status"], nonsense: ["git zzz"]).isCutMidWord)
        #expect(!Calibration.Probe("git", sensible: ["git"], nonsense: ["git x"]).isCutMidWord)
        #expect(!Calibration.Probe("git s", sensible: ["git status"], nonsense: ["svn status"]).isCutMidWord)
    }

    @Test func theTableHasOneRowPerFloorAndSaysWhenLinesWentUnscored() {
        let scored = [
            Calibration.Scored(typed: "gi", line: "git status", isSensible: true, score: -2),
            Calibration.Scored(typed: "gi", line: "gizmo", isSensible: false, score: nil),
        ]
        let table = Calibration.markdown(scored, floors: [-6, -3])
        #expect(table.contains("| -6.0 | 1 of 1 | 0 of 0 |"))
        #expect(table.contains("| -3.0 | 1 of 1 | 0 of 0 |"))
        #expect(table.contains("1 lines had no score"))
    }
}
