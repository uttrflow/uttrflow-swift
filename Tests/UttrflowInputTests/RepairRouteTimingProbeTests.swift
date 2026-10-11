// Times the machine side of each recovery route on the insertion fixture. See Docs/repair-cost.md.
import AppKit
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// The middle, the 95th percentile and a 95% band on the mean of a set of timings, in milliseconds.
struct TimingSummary: Equatable {
    let count: Int
    let median: Double
    let p95: Double
    let low: Double
    let high: Double

    /// Nearest-rank percentiles and a normal band on the mean; nil for fewer than two timings.
    init?(_ timings: [Double]) {
        guard timings.count > 1 else { return nil }
        let sorted = timings.sorted()
        func rank(_ fraction: Double) -> Double {
            sorted[min(sorted.count - 1, max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1))]
        }
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let variance = sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(sorted.count - 1)
        let half = 1.96 * (variance / Double(sorted.count)).squareRoot()
        count = sorted.count
        median = rank(0.5)
        p95 = rank(0.95)
        low = mean - half
        high = mean + half
    }

    /// One table row: N, median, p95 and the band, to the hundredth of a millisecond.
    var row: String {
        String(
            format: "N=%d median %.2f ms, p95 %.2f ms, mean 95%% %.2f-%.2f ms", count, median, p95, low, high)
    }
}

@Suite("Summarising route timings")
struct TimingSummaryTests {
    @Test("takes nearest-rank percentiles and a band around the mean")
    func summarises() throws {
        let summary = try #require(TimingSummary([4, 1, 3, 2, 5, 6, 7, 8, 9, 10]))
        #expect(summary.count == 10)
        #expect(summary.median == 5)
        #expect(summary.p95 == 10)
        #expect(abs((summary.low + summary.high) / 2 - 5.5) < 1e-9)
        #expect(summary.low < 5.5 && summary.high > 5.5)
    }

    @Test("refuses a single timing, which has no spread", arguments: [[Double](), [3.0]])
    func refusesOne(timings: [Double]) {
        #expect(TimingSummary(timings) == nil)
    }
}

/// An Accessibility element of the fixture, passed between threads as the app's own reader passes its.
private struct FixtureElement: @unchecked Sendable {
    let element: AXUIElement

    func attribute(_ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    var processIdentifier: pid_t? {
        var owner: pid_t = 0
        return AXUIElementGetPid(element, &owner) == .success ? owner : nil
    }

    /// The first element at or under this one that `matches`, searched depth first.
    func first(depth: Int = 0, where matches: (FixtureElement) -> Bool) -> FixtureElement? {
        if matches(self) { return self }
        guard depth < 8, let children = attribute(kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let found = FixtureElement(element: child).first(depth: depth + 1, where: matches) {
                return found
            }
        }
        return nil
    }
}

/// The fixture field's selection attributes, read and written only through its own element.
private struct FixtureAttributes: SelectionAttributes {
    let field: FixtureElement

    func value() -> String? { field.attribute(kAXValueAttribute) as? String }
    func length() -> Int? { value()?.utf16.count }

    func text(in range: Range<Int>) -> String? {
        guard let value = value(), range.lowerBound >= 0, range.upperBound <= value.utf16.count else {
            return nil
        }
        let units = Array(value.utf16)[range]
        return String(decoding: units, as: UTF16.self)
    }

    func selectedRange() -> CFRange? {
        guard let raw = field.attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        // Checked by type ID above; `as?` on a Core Foundation type always succeeds.
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cfRange, &range) ? range : nil
    }

    func setSelectedText(_ text: String) -> AXError {
        AXUIElementSetAttributeValue(field.element, kAXSelectedTextAttribute as CFString, text as CFString)
    }

    func setSelectedRange(_ range: CFRange) -> AXError {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return .illegalArgument }
        return AXUIElementSetAttributeValue(field.element, kAXSelectedTextRangeAttribute as CFString, value)
    }
}

/// A focus that only ever names the fixture's field, so no write can reach whatever window is in front.
private struct FixtureFocus: AccessibilityFocus {
    let field: FixtureElement
    let processIdentifier: pid_t

    /// Every write goes through here first, and refuses unless the field still belongs to the fixture.
    private var owned: Bool { field.processIdentifier == processIdentifier }

    private var identity: FieldIdentity {
        FieldIdentity(
            processIdentifier: processIdentifier, windowNumber: nil,
            element: Int(bitPattern: CFHash(field.element)))
    }

    func focusedTextField() -> (any FocusedTextField)? {
        owned ? SelectionWriter(field: FixtureAttributes(field: field)) : nil
    }

    func hasFocusedElement() -> Bool { owned }
    func isSelfFrontmost() -> Bool { false }
    func focusedFieldIdentity() -> FieldIdentity? { owned ? identity : nil }

    func focusedFieldPlace() -> FieldPlace? {
        guard owned, let range = FixtureAttributes(field: field).selectedRange(), range.length == 0 else {
            return nil
        }
        return FieldPlace(field: identity, caret: range.location)
    }

    func focusedApplication() -> InsertionDestination? {
        InsertionDestination(
            applicationName: "uttrflow-insertion-fixture", bundleIdentifier: nil,
            processIdentifier: processIdentifier)
    }
}

/// The fixture process this probe launched, and the two elements it drives: the multi-line field and Edit > Undo.
private struct LaunchedFixture {
    let process: Process
    let focus: FixtureFocus
    let undo: FixtureElement

    static let binary = ProcessInfo.processInfo.environment["UTTRFLOW_INSERTION_FIXTURE"]

    static func launch(_ binary: String) throws -> LaunchedFixture {
        let report = FileManager.default.temporaryDirectory.appendingPathComponent(
            "repair-timing-\(UUID()).json")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--mode", "faithful", "--focus", "multiline", "--report", report.path]
        try process.run()
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: report.path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)
        let pid = process.processIdentifier
        let application = FixtureElement(element: AXUIElementCreateApplication(pid))
        guard
            let field = application.first(where: {
                ($0.attribute(kAXDescriptionAttribute) as? String) == "multiline"
            }),
            let bar = application.attribute(kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID(),
            let undo = FixtureElement(element: unsafeDowncast(bar, to: AXUIElement.self)).first(where: {
                ($0.attribute(kAXTitleAttribute) as? String) == "Undo"
            }),
            field.processIdentifier == pid, undo.processIdentifier == pid
        else {
            process.terminate()
            throw FixtureUnreachable()
        }
        return LaunchedFixture(
            process: process, focus: FixtureFocus(field: field, processIdentifier: pid), undo: undo)
    }

    var value: String? { FixtureAttributes(field: focus.field).value() }

    /// Presses the fixture's own Undo item through Accessibility; no key is posted anywhere.
    func pressUndo() throws {
        guard process.isRunning, undo.processIdentifier == process.processIdentifier else {
            throw FixtureUnreachable()
        }
        guard AXUIElementPerformAction(undo.element, kAXPressAction as CFString) == .success else {
            throw FixtureUnreachable()
        }
    }

    /// Reads the field until it holds `expected`, giving up after two seconds.
    func waitFor(_ expected: String) -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if value == expected { return true }
            Thread.sleep(forTimeInterval: 0.0002)
        }
        return false
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
    }
}

private struct FixtureUnreachable: Error {}

@Suite(
    "Machine time of each recovery route on the insertion fixture",
    .serialized,
    .enabled(
        if: LaunchedFixture.binary != nil,
        "set UTTRFLOW_INSERTION_FIXTURE to the built fixture and grant Accessibility to the shell"))
struct RepairRouteTimingProbeTests {
    /// A 100-word dictation, the size `Scripts/repair_cost.py` prices.
    static let dictation = Array(
        repeating: "every route is timed on the same plain words here once", count: 10
    )
    .joined(separator: " ")

    /// "replace once with twice": the last "once" only, the match nearest the end as the spoken command takes it.
    @Sendable static func lastOnce(_ text: String) -> String {
        guard let last = text.range(of: "once", options: .backwards) else { return text }
        return text.replacingCharacters(in: last, with: "twice")
    }

    @Test("prints the median, p95 and band of each route's machine wait, with N")
    func timesRoutes() async throws {
        #expect(AXIsProcessTrusted(), "grant Accessibility to the shell running the probe")
        let runs = Int(ProcessInfo.processInfo.environment["UTTRFLOW_REPAIR_TIMING_RUNS"] ?? "") ?? 50
        let fixture = try LaunchedFixture.launch(try #require(LaunchedFixture.binary))
        defer { fixture.stop() }
        let clock = ContinuousClock()
        var timings: [String: [Double]] = [:]
        let replaced = Self.lastOnce(Self.dictation)
        for run in 0..<(runs + 3) {
            try #require(fixture.value == "", "the field must start empty")
            func time(_ route: String, _ body: () async throws -> Void) async throws {
                let start = clock.now
                try await body()
                // The first three runs warm the fixture and the Accessibility server, and are not kept.
                if run >= 3 {
                    timings[route, default: []].append(start.duration(to: clock.now).inMilliseconds)
                }
            }
            func insert() async throws -> InsertionLedger {
                let ledger = InsertionLedger()
                let coordinator = TextInsertionCoordinator(
                    strategies: [AccessibilityTextInsertionEngine(focus: fixture.focus)],
                    focus: fixture.focus,
                    ledger: ledger)
                try await time("insert, 100 words") {
                    let attempt = try await coordinator.insert(Self.dictation)
                    try #require(attempt.method == .accessibility && attempt.arrival == .confirmed)
                }
                return ledger
            }

            let spoken = RecordedEditor(
                ledger: try await insert(), history: EditHistory(), focus: fixture.focus)
            try await time("undo that") { try await spoken.run(.undo) }
            try #require(fixture.value == "")

            _ = try await insert()
            try await time("app undo") {
                try fixture.pressUndo()
                try #require(fixture.waitFor(""))
            }

            let replace = RecordedEditor(
                ledger: try await insert(), history: EditHistory(), focus: fixture.focus)
            try await time("replace X with Y") {
                try await replace.rewrite(Self.lastOnce)
            }
            try #require(fixture.value == replaced)
            try fixture.pressUndo()
            try #require(fixture.waitFor(Self.dictation))
            try fixture.pressUndo()
            try #require(fixture.waitFor(""))
        }
        for (route, values) in timings.sorted(by: { $0.key < $1.key }) {
            let summary = try #require(TimingSummary(values))
            print("repair timing: \(route): \(summary.row)")
        }
    }
}

extension Duration {
    fileprivate var inMilliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}
