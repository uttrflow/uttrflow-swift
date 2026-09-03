import Testing

@testable import UttrflowContext

/// Builds a reading, so each test names only what it is about.
private func reading(
    application: String = "Terminal",
    role: String? = "AXTextArea",
    locator: String? = nil,
    value: Bool = true,
    caret: Bool = true,
    style: Bool = true,
    secure: Bool = false,
    microseconds: Int = 100
) -> SurfaceCapability {
    SurfaceCapability(
        application: application, role: role, locator: locator, reportsValue: value,
        reportsCaretRect: caret,
        reportsTextStyle: style, isSecure: secure, readMicroseconds: microseconds)
}

@Suite("The placement ladder")
struct PlacementTests {
    @Test("A field that answers everything takes the inline ghost.")
    func everything() {
        #expect(reading().placement == .inlineGhost)
    }

    @Test("A field that hides its styling still takes the inline ghost, in a defaulted font.")
    func noStyle() {
        #expect(reading(style: false).placement == .inlineGhost)
    }

    @Test("A field that hides its caret falls to the window strip.")
    func noCaret() {
        #expect(reading(caret: false, style: false).placement == .windowStrip)
    }

    @Test("Styling without a caret is still the window strip, because there is nowhere to draw.")
    func styleWithoutCaret() {
        #expect(reading(caret: false).placement == .windowStrip)
    }

    @Test("A field whose text cannot be read gets nothing, because nothing can be predicted.")
    func noValue() {
        #expect(reading(value: false).placement == nil)
    }

    @Test("A secure field gets nothing, however much else it answers.")
    func secure() {
        #expect(reading(secure: true).placement == nil)
    }

    @Test("The ladder orders best first.")
    func order() {
        #expect(SuggestionPlacement.inlineGhost < SuggestionPlacement.windowStrip)
    }
}

@Suite("Sweeping a set of fields")
struct SweepTests {
    @Test("An empty sweep decides nothing and refuses to recommend the ghost.")
    func empty() {
        let sweep = CapabilitySweep()
        #expect(sweep.isEmpty)
        #expect(sweep.inlineShare == 0)
        #expect(sweep.eligibleShare == 0)
        #expect(!sweep.inlineIsWorthBuilding)
    }

    @Test("The same field read twice is one reading, not two.")
    func deduplicates() {
        let sweep = CapabilitySweep([reading(), reading()])
        #expect(sweep.readings.count == 1)
    }

    @Test("A later reading that saw more replaces one that saw less.")
    func keepsTheBest() {
        let sweep = CapabilitySweep([reading(caret: false, style: false), reading()])
        #expect(sweep.readings.first?.placement == .inlineGhost)
    }

    @Test("A later reading that saw less does not undo one that saw more.")
    func keepsTheBestWhicheverWayRound() {
        let sweep = CapabilitySweep([reading(), reading(caret: false, style: false)])
        #expect(sweep.readings.first?.placement == .inlineGhost)
    }

    @Test("Two roles in one application are two fields.")
    func rolesAreSeparate() {
        let sweep = CapabilitySweep([reading(role: "AXTextArea"), reading(role: "AXTextField")])
        #expect(sweep.readings.count == 2)
    }

    @Test("Two fields of one role in one application stay apart when they name themselves.")
    func locatorsAreSeparate() {
        let sweep = CapabilitySweep([reading(locator: "omnibox"), reading(locator: "search")])
        #expect(sweep.readings.count == 2)
        #expect(sweep.readings.map(\.locator) == ["omnibox", "search"])
    }

    @Test("A field with no role at all is still recorded.")
    func missingRole() {
        let sweep = CapabilitySweep([reading(role: nil, caret: false, style: false)])
        #expect(sweep.readings.count == 1)
        #expect(sweep.count(of: .windowStrip) == 1)
    }

    @Test("Readings come back ordered, so two runs of the probe read alike.")
    func ordered() {
        let sweep = CapabilitySweep([reading(application: "Slack"), reading(application: "Chrome")])
        #expect(sweep.readings.map(\.application) == ["Chrome", "Slack"])
    }

    @Test("Shares count every field, including the ones that can take nothing.")
    func shares() {
        let sweep = CapabilitySweep([
            reading(application: "A"),
            reading(application: "B", style: false),
            reading(application: "C", caret: false, style: false),
            reading(application: "D", secure: true),
        ])
        // A and B both reach the inline ghost now, because a caret is all it needs.
        #expect(sweep.inlineShare == 0.5)
        #expect(sweep.eligibleShare == 0.75)
        #expect(sweep.count(of: nil) == 1)
    }

    @Test("At the threshold the ghost is worth building; below it, it is not.")
    func threshold() {
        let atThreshold = CapabilitySweep([
            reading(application: "A"), reading(application: "B", caret: false, style: false),
            reading(application: "C", caret: false, style: false),
        ])
        #expect(atThreshold.inlineShare >= CapabilitySweep.inlineThreshold)
        #expect(atThreshold.inlineIsWorthBuilding)

        let below = CapabilitySweep([
            reading(application: "A"), reading(application: "B", caret: false, style: false),
            reading(application: "C", caret: false, style: false),
            reading(application: "D", caret: false, style: false),
        ])
        #expect(!below.inlineIsWorthBuilding)
    }
}

@Suite("The report the operator reads")
struct ProbeReportTests {
    @Test("An empty sweep says so rather than printing an empty table.")
    func empty() {
        #expect(ProbeReport(CapabilitySweep()).markdown().contains("No fields were read"))
    }

    @Test("Every field becomes a row, under one header.")
    func rows() {
        let markdown = ProbeReport(
            CapabilitySweep([reading(application: "Terminal"), reading(application: "Chrome")])
        ).markdown()
        #expect(markdown.contains("| Terminal | AXTextArea |"))
        #expect(markdown.contains("| Chrome | AXTextArea |"))
        #expect(markdown.components(separatedBy: "| Application |").count == 2)
    }

    @Test("A pipe in an application name does not break the table.")
    func escapesPipes() {
        let markdown = ProbeReport(CapabilitySweep([reading(application: "a|b")])).markdown()
        #expect(markdown.contains("a\\|b"))
    }

    @Test("Enough inline fields and the report says to build the ladder.")
    func recommendsTheLadder() {
        #expect(ProbeReport(CapabilitySweep([reading()])).markdown().contains("Build the ladder"))
    }

    @Test("Too few and it says the strip is the product.")
    func recommendsTheStrip() {
        let markdown = ProbeReport(
            CapabilitySweep([reading(caret: false, style: false)])
        ).markdown()
        #expect(markdown.contains("window strip as the product"))
    }

    @Test("A field that can take nothing is reported as taking nothing.")
    func reportsRefusal() {
        #expect(ProbeReport(CapabilitySweep([reading(secure: true)])).markdown().contains("nothing"))
    }
}
