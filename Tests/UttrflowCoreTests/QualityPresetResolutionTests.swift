import Testing

@testable import UttrflowCore

@Suite("The quality preset an app is dictated under reaches its formatter and its steps")
struct QualityPresetResolutionTests {
    private let bundle = "com.example.editor"

    private func situation(_ overrides: DestinationOverrides, role: String? = nil) -> Situation {
        SituationResolver.resolve(
            from: AppContext(applicationName: "Editor", bundleIdentifier: bundle, accessibilityRole: role),
            overrides: overrides)
    }

    @Test("with no preset chosen, the place's own formatter and the user's steps are used unchanged")
    func standardChangesNothing() {
        let plain = situation(.none)
        #expect(DestinationFormatter.standard(for: plain) == .standard(for: plain.destination))
        #expect(plain.cleaningSteps(.default) == .default)
    }

    @Test("the preset for every app chooses the formatter's policies")
    func everyAppPresetReachesFormatter() {
        let formatter = DestinationFormatter.standard(for: situation(.none.holding(everyApp: .code)))
        #expect(formatter.firstWord == .asSpoken)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.numbers == .always)
        #expect(formatter.layout == .preserveNewlines)
    }

    @Test("an app's own preset wins over the one for every app, and switches its steps off")
    func appPresetWins() {
        let overrides = DestinationOverrides.none.setting(
            preset: .verbatim, for: bundle, named: "Editor", fallback: .plain
        ).holding(everyApp: .code)
        let own = situation(overrides)
        #expect(DestinationFormatter.standard(for: own) == .standard(for: own.destination))
        #expect(!own.cleaningSteps(.default).runs(.fillers))
        #expect(!own.cleaningSteps(.default).runs(.selfCorrection))
        let other = SituationResolver.resolve(
            from: AppContext(bundleIdentifier: "com.example.other"), overrides: overrides)
        #expect(DestinationFormatter.standard(for: other).numbers == .always)
        #expect(other.cleaningSteps(.default).runs(.fillers))
    }

    @Test("a one-line field stays one line under a preset that keeps line breaks")
    func oneLineFieldStaysOneLine() {
        let formatter = DestinationFormatter.standard(
            for: situation(.none.holding(everyApp: .code), role: "AXTextField"))
        #expect(formatter.layout.contains(.singleLine))
        #expect(!formatter.layout.contains(.preserveNewlines))
        #expect(formatter.terminalStop == .never)
    }

    @Test("the final stop the person fixed for an app wins over the app's preset")
    func fixedStopWins() {
        let overrides = DestinationOverrides.none.setting(
            punctuation: AppPunctuation(finalStop: .always), for: bundle, named: "Editor", fallback: .plain
        ).holding(everyApp: .code)
        let formatter = DestinationFormatter.standard(for: situation(overrides))
        #expect(formatter.terminalStop == .always)
        #expect(formatter.numbers == .always)
    }
}
