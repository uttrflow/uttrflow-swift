import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

enum DiagnosticsFixture {
    static let locale = Locale(identifier: "en_GB")

    static func timing(
        _ stage: PipelineStage, _ seconds: Double, succeeded: Bool = true
    ) -> StageMeasurement {
        StageMeasurement(
            stage: stage, duration: .milliseconds(Int(seconds * 1000)), succeeded: succeeded)
    }

    static func page(
        engines: EngineConfiguration = .default,
        availability: [TransformerKind: Bool] = [:],
        model: DiagnosticsModelPresence? = nil,
        permissions: [PermissionKind: PermissionStatus] = [:],
        measurements: [StageMeasurement] = [],
        cleaning: CleaningRecord? = nil
    ) -> DiagnosticsPresentation {
        DiagnosticsPresenter.page(
            for: DiagnosticsSnapshot(
                engines: engines, transformerAvailability: availability, speechModel: model,
                permissions: permissions, measurements: measurements, cleaning: cleaning),
            locale: locale)
    }
}

@Suite("Diagnostics reports only what was measured")
struct DiagnosticsLatencyTests {
    /// One of everything, which is what the app records for a dictation that ran the
    /// whole way through.
    static let wholeJourney = PipelineStage.allCases.map { DiagnosticsFixture.timing($0, 1) }

    /// The pipeline times transcription, clean-up and insertion. Nothing timed capture
    /// here, so capture has no row of numbers — an absent measurement is not a zero.
    @Test("a stage nobody timed has no row of numbers")
    func unmeasuredStagesAreAbsent() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1.9),
            DiagnosticsFixture.timing(.transformation, 0.68),
            DiagnosticsFixture.timing(.insertion, 0.04),
        ])

        #expect(page.latency?.stages.map(\.stage) == [.transcription, .transformation, .insertion])
        #expect(page.latency?.stages.map(\.title) == ["Transcribing", "Tidying up", "Inserting"])
    }

    /// Every stage of the journey, named the way the rest of the product names it.
    @Test("every stage the pipeline measures has a row and a name")
    func everyStageIsNamed() {
        let page = DiagnosticsFixture.page(measurements: Self.wholeJourney)

        #expect(page.latency?.stages.map(\.stage) == PipelineStage.allCases)
        #expect(
            page.latency?.stages.map(\.title) == [
                "Recording", "Transcribing", "Checking the dictionary", "Tidying up",
                "Expanding snippets", "Inserting",
            ])
        #expect(page.latency?.unmeasured.isEmpty == true)
    }

    /// The distinction the whole page is built on. A stage that has never run is named,
    /// in the page's own vocabulary for "not known", rather than drawn as a fast one.
    @Test("a stage that has never run is reported as never run, not as no time")
    func neverRunIsNotZero() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1.9),
            StageMeasurement(stage: .correction, duration: .zero, succeeded: true),
        ])

        #expect(page.latency?.stages.map(\.stage) == [.transcription, .correction])
        #expect(page.latency?.stages.last?.typical == "under 0.01s", "measured, and instant")
        #expect(
            page.latency?.unmeasured.map(\.title) == [
                "Recording", "Tidying up", "Expanding snippets", "Inserting",
            ])
        #expect(page.latency?.unmeasured.allSatisfy { $0.detail == "Never run" } == true)
        #expect(page.latency?.unmeasured.allSatisfy { $0.state == .unknown } == true)
    }

    /// The rule applied to the total: a sum of four stages out of six is a floor, and
    /// the headline is where a reader takes the number from.
    @Test("a total missing a stage says it is a floor rather than a time")
    func incompleteTotalSaysSo() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1.9),
            DiagnosticsFixture.timing(.insertion, 0.1),
        ])

        #expect(page.latency?.headline == "at least 2.00s")
        #expect(page.latency?.caption.hasSuffix("without 4 stages nothing has ever timed") == true)
    }

    /// And withdrawn once there is nothing missing: "at least" on a complete journey
    /// would be its own small lie.
    @Test("a complete journey states its total plainly")
    func completeTotalIsPlain() {
        let page = DiagnosticsFixture.page(measurements: Self.wholeJourney)

        #expect(page.latency?.headline == "6.00s")
        #expect(page.latency?.caption == "each stage's typical time, added together, over 1 dictation")
    }

    @Test("nothing measured means the page says so rather than drawing an empty chart")
    func nothingMeasured() {
        let page = DiagnosticsFixture.page()
        #expect(page.latency == nil)
        #expect(page.latencyEmptyState?.title == "No timings yet")
        #expect(page.reliability.isEmpty)
    }

    /// A mean would let one pathological dictation move the number a user reads as
    /// "what usually happens".
    @Test("the typical time is the middle measurement, not the average")
    func typicalIsTheMiddle() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1),
            DiagnosticsFixture.timing(.transcription, 2),
            DiagnosticsFixture.timing(.transcription, 30),
        ])

        #expect(page.latency?.stages.first?.typical == "2.00s")
        #expect(page.latency?.stages.first?.slowest == "30.00s")
        #expect(page.latency?.stages.first?.samples == 3)
    }

    @Test("the headline is the stage typicals added together, and says so")
    func headlineIsASumOfTypicals() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1.9),
            DiagnosticsFixture.timing(.transformation, 0.68),
            DiagnosticsFixture.timing(.insertion, 0.04),
        ])

        #expect(page.latency?.headline == "at least 2.62s", "three of the six stages are missing")
        #expect(
            page.latency?.caption == """
                each stage's typical time, added together, over 1 dictation, without \
                3 stages nothing has ever timed
                """)
    }

    @Test("the caption counts the dictations behind the numbers")
    func captionCountsDictations() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1),
            DiagnosticsFixture.timing(.transcription, 1),
        ])
        #expect(page.latency?.caption.contains("over 2 dictations,") == true)
    }

    /// The bar is drawn from these, so they have to add up to the whole of it.
    @Test("the shares divide the bar between the stages")
    func sharesDivideTheBar() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 3),
            DiagnosticsFixture.timing(.insertion, 1),
        ])
        let shares = page.latency?.stages.map(\.share) ?? []

        #expect(shares.count == 2)
        #expect(abs(shares.reduce(0, +) - 1) < 0.000_1)
        #expect(abs(shares[0] - 0.75) < 0.000_1)
    }

    /// A journey with no time in it divides zero by zero; a flat bar is the truthful
    /// picture of that, and a crash is not.
    @Test("stages that took no time at all leave the bar empty")
    func zeroDurationsDoNotDivideByZero() {
        let page = DiagnosticsFixture.page(measurements: [
            StageMeasurement(stage: .transcription, duration: .zero, succeeded: true)
        ])

        #expect(page.latency?.stages.first?.share == 0)
        // Never "at least under 0.01s": an upper bound is the one thing a total with
        // five stages missing from it cannot claim.
        #expect(page.latency?.headline == "at least 0.00s")
    }

    /// Capture is not measured today, but the page must not have to change when it is.
    @Test("a newly measured stage appears in journey order without any other change")
    func measuringCaptureWouldJustWork() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.insertion, 0.1),
            DiagnosticsFixture.timing(.capture, 4),
        ])

        #expect(page.latency?.stages.map(\.stage) == [.capture, .insertion])
        #expect(page.latency?.stages.first?.title == "Recording")
    }

    @Test("a stage row is identified by its stage")
    func stageRowIdentity() {
        let summaries = DiagnosticsPresenter.summaries(for: [
            DiagnosticsFixture.timing(.insertion, 0.1)
        ])
        #expect(DiagnosticsPresenter.stageRows(for: summaries).first?.id == .insertion)
    }
}

@Suite("Diagnostics reports how often things worked")
struct DiagnosticsReliabilityTests {
    @Test("a stage's success rate comes from the successes recorded against it")
    func successRate() {
        let page = DiagnosticsFixture.page(measurements: [
            DiagnosticsFixture.timing(.transcription, 1),
            DiagnosticsFixture.timing(.transcription, 1),
            DiagnosticsFixture.timing(.transcription, 1, succeeded: false),
            DiagnosticsFixture.timing(.insertion, 1),
        ])

        #expect(page.reliability.map(\.caption) == ["Transcribing worked", "Inserting worked"])
        #expect(page.reliability.first?.value == "66.7%")
        #expect(page.reliability.last?.value == "100.0%")
    }

    /// A percentage with nothing behind it is not a measurement.
    @Test("a stage with no attempts has no percentage")
    func noAttemptsNoPercentage() {
        let page = DiagnosticsFixture.page(measurements: [DiagnosticsFixture.timing(.insertion, 1)])
        #expect(page.reliability.count == 1)
    }
}

@Suite("Diagnostics reports what is running")
struct DiagnosticsEngineTests {
    @Test("the speech engine is always named, and the clean-up order is kept")
    func enginesFollowTheConfiguration() {
        let page = DiagnosticsFixture.page(
            availability: [.foundationModels: true, .localModel: true, .rules: true])

        #expect(page.engines.first?.title == "Speech")
        #expect(page.engines.first?.detail == "Downloaded speech model")
        #expect(
            page.engines.dropFirst().map(\.title) == [
                "Built-in language model", "Built-in rules",
            ],
            "the page must list only engines this build actually contains")
    }

    /// The first one that can run is the one that runs; the rest are standing by.
    @Test("only the first available clean-up engine is in use")
    func firstAvailableIsInUse() {
        let page = DiagnosticsFixture.page(
            availability: [.foundationModels: false, .localModel: true, .rules: true])
        let details = page.engines.dropFirst().map(\.detail)

        #expect(details == ["Not available on this Mac", "In use"])
        #expect(page.engines.dropFirst().map(\.state) == [.attention, .good])
    }

    /// "No" and "nobody has asked yet" are different answers, and a diagnostics page
    /// that cannot tell them apart will eventually say something untrue.
    @Test("an engine nobody has asked about is unknown, not unavailable")
    func unaskedEnginesAreUnknown() {
        let page = DiagnosticsFixture.page()
        #expect(page.engines.dropFirst().allSatisfy { $0.state == .unknown })
        #expect(page.engines.dropFirst().allSatisfy { $0.detail == "Not checked yet" })
    }

    @Test("the built-in recogniser is named as such")
    func systemSpeechEngine() {
        let page = DiagnosticsFixture.page(
            engines: EngineConfiguration(speech: .appleSpeech, transformerPreference: [.rules]))
        #expect(page.engines.first?.detail == "Built-in speech recognition")
    }

    /// §16: the user must never learn which engine ran. A diagnostics page is still the
    /// user's, so it says what kind of thing is running and never what it is called.
    @Test("no engine is named after the thing it actually is")
    func noProductNamesAnywhere() {
        let forbidden = [
            "whisper", "openai", "foundation", "apple", "mlx", "qwen", "llama", "gpt", "kit",
        ]
        var names = SpeechEngineKind.allCases.map(DiagnosticsPresenter.name(for:))
        names += TransformerKind.allCases.map(DiagnosticsPresenter.name(for:))

        for name in names {
            let lowercased = name.lowercased()
            #expect(!forbidden.contains { lowercased.contains($0) }, "\(name) names an engine")
        }
    }
}

@Suite("Diagnostics reports what is in the way")
struct DiagnosticsPermissionTests {
    /// A page that lists only the broken permissions cannot be used to confirm that
    /// nothing is broken.
    @Test("every permission is listed, granted or not")
    func everyPermissionIsListed() {
        let page = DiagnosticsFixture.page(permissions: [.microphone: .granted])
        #expect(page.permissions.map(\.title) == ["Microphone", "Accessibility"])
        #expect(page.permissions.first?.state == .good)
        #expect(page.permissions.first?.detail == "Granted")
    }

    @Test("a denied permission offers the way to fix it")
    func deniedOffersSettings() {
        let page = DiagnosticsFixture.page(permissions: [.accessibility: .denied])
        let row = page.permissions.last
        #expect(row?.detail == "Turned off")
        #expect(row?.state == .attention)
        #expect(row?.action?.intent == .recover(.openSystemSettings(.accessibility)))
    }

    @Test("a permission never asked for sends the user to setting up")
    func notDeterminedOffersOnboarding() {
        let page = DiagnosticsFixture.page(permissions: [.microphone: .notDetermined])
        #expect(page.permissions.first?.detail == "Not asked for yet")
        #expect(page.permissions.first?.action?.intent == .go(.onboarding))
    }

    /// Asking again cannot help, so nothing is offered.
    @Test("a permission blocked by policy offers nothing to click")
    func restrictedOffersNothing() {
        let page = DiagnosticsFixture.page(permissions: [.microphone: .restricted])
        #expect(page.permissions.first?.detail == "Blocked by a device policy")
        #expect(page.permissions.first?.action == nil)
    }

    @Test("an unchecked permission is reported as unchecked")
    func uncheckedIsUnknown() {
        let page = DiagnosticsFixture.page()
        #expect(page.permissions.allSatisfy { $0.state == .unknown })
    }

    @Test("a row is identified by what it reports on")
    func rowIdentity() {
        #expect(DiagnosticsFixture.page().permissions.first?.id == "Microphone")
    }
}

@Suite("Diagnostics reports what is on the disk")
struct DiagnosticsStorageTests {
    @Test("an installed model reports its size and what it covers")
    func installedModel() {
        let page = DiagnosticsFixture.page(
            model: DiagnosticsModelPresence(
                isInstalled: true, bytesOnDisk: 645_668_913, isMultilingual: true))
        let row = page.storage.first

        #expect(row?.state == .good)
        #expect(row?.detail.contains("MB") == true)
        #expect(row?.detail.hasSuffix("on this Mac, every language") == true)
    }

    @Test("a model of unknown size still reports that it is there")
    func installedModelWithoutASize() {
        let page = DiagnosticsFixture.page(
            model: DiagnosticsModelPresence(
                isInstalled: true, bytesOnDisk: nil, isMultilingual: false))
        #expect(page.storage.first?.detail == "on this Mac, English")
    }

    @Test("a missing model offers to fetch it")
    func missingModel() {
        let page = DiagnosticsFixture.page(
            model: DiagnosticsModelPresence(
                isInstalled: false, bytesOnDisk: nil, isMultilingual: true))

        #expect(page.storage.first?.detail == "Not downloaded")
        #expect(page.storage.first?.action?.intent == .recover(.downloadSpeechModel))
    }

    @Test("a store nobody has consulted is unknown rather than empty")
    func unconsultedStore() {
        #expect(DiagnosticsFixture.page().storage.first?.state == .unknown)
    }
}

@Suite("Diagnostics can be copied out")
struct DiagnosticsReportTests {
    /// What is copied must not say something different from what was on screen.
    @Test("the report carries the same numbers the page shows")
    func reportMatchesThePage() {
        let snapshot = DiagnosticsSnapshot(
            permissions: [.microphone: .granted],
            measurements: [DiagnosticsFixture.timing(.transcription, 1.9)])
        let report = DiagnosticsPresenter.report(for: snapshot, locale: DiagnosticsFixture.locale)

        #expect(report.contains("Transcribing: 1.90s / 1.90s / 1"))
        #expect(
            report.contains("Checking the dictionary: never run"),
            "a bug report that lists two stages of a six-stage journey is about the wrong two")
        #expect(report.contains("Microphone: Granted"))
        #expect(report.contains(DiagnosticsPresenter.footnote))
        #expect(report.contains("On disk"))
    }

    @Test("a report with nothing measured says so rather than showing a blank")
    func reportWithoutMeasurements() {
        let report = DiagnosticsPresenter.report(
            for: DiagnosticsSnapshot(), locale: DiagnosticsFixture.locale)
        #expect(report.contains("Timings: none recorded yet"))
    }

    @Test("the copy button carries the report")
    func copyActionCarriesTheReport() {
        let page = DiagnosticsFixture.page()
        #expect(page.copyAction.title == "Copy Diagnostics")
        #expect(
            page.copyAction.intent
                == .copy(
                    DiagnosticsPresenter.report(
                        for: DiagnosticsSnapshot(), locale: DiagnosticsFixture.locale)))
    }

    /// The window the numbers cover begins when the app starts, and the page says so
    /// rather than implying a history it does not keep.
    @Test("the footnote is honest about the window and about where the numbers stay")
    func footnoteIsHonest() {
        #expect(DiagnosticsFixture.page().footnote.contains("since Uttrflow started"))
        #expect(DiagnosticsFixture.page().footnote.contains("never sent anywhere"))
    }
}

@Suite("Keeping the measurements")
struct DiagnosticsRecorderTests {
    /// The page's footnote says the window begins when Uttrflow started. Adding a stage
    /// without widening this quietly shortens it, and nothing on screen would say so.
    @Test("holds a hundred whole dictations, whatever a dictation is made of")
    func capacityCoversAHundredDictations() {
        #expect(DiagnosticsRecorder.defaultCapacity >= PipelineStage.allCases.count * 100)
    }

    @Test("what the pipeline measures is what the page reads")
    func keepsWhatItIsGiven() async {
        let recorder = DiagnosticsRecorder()
        await recorder.record(DiagnosticsFixture.timing(.transcription, 1))
        await recorder.record(DiagnosticsFixture.timing(.insertion, 0.1, succeeded: false))

        let recorded = await recorder.recorded
        #expect(recorded.map(\.stage) == [.transcription, .insertion])
        #expect(recorded.map(\.succeeded) == [true, false])
    }

    /// Bounded, because this is a file about the user's habits that nobody asked for if
    /// it is allowed to grow without limit.
    @Test("the oldest measurements are dropped once it is full")
    func dropsTheOldest() async {
        let recorder = DiagnosticsRecorder(capacity: 2)
        for stage in [PipelineStage.capture, .transcription, .insertion] {
            await recorder.record(DiagnosticsFixture.timing(stage, 1))
        }

        #expect(await recorder.recorded.map(\.stage) == [.transcription, .insertion])
    }

    /// Clamped rather than trusted: no diagnostics is better than a crash.
    @Test("a capacity that makes no sense keeps nothing rather than trapping")
    func nonsensicalCapacity() async {
        let recorder = DiagnosticsRecorder(capacity: -5)
        await recorder.record(DiagnosticsFixture.timing(.insertion, 1))
        #expect(await recorder.recorded.isEmpty)
    }

    /// The pipeline records through `measuring`, so that is the path worth exercising:
    /// handing this recorder in is the whole of the wiring the app has to get right.
    @Test("timing something through the pipeline's own helper lands here")
    func recordsThroughMeasuring() async {
        let recorder = DiagnosticsRecorder()
        let value = await recorder.measuring(.transformation, clock: ContinuousClock()) { 42 }

        #expect(value == 42)
        #expect(await recorder.recorded.map(\.stage) == [.transformation])
        #expect(await recorder.recorded.allSatisfy(\.succeeded))
    }
}

@Suite("Diagnostics says what needs doing, above what it measured")
struct DiagnosticsSummaryTests {
    /// The page is a page of facts, and a page of facts makes the reader decide which
    /// fact matters. This is the answer to the question they arrived with.
    @Test("names the first thing wrong, and carries its own fix")
    func namesTheProblem() {
        let page = DiagnosticsFixture.page(permissions: [.accessibility: .denied])

        #expect(page.summary.needsAttention)
        #expect(page.summary.text == "Accessibility: Turned off")
        #expect(page.summary.action?.intent == .recover(.openSystemSettings(.accessibility)))
    }

    /// Permissions first: a permission that is not granted means no dictation at all,
    /// where an engine that is not ready only means a worse one is being used.
    @Test("a missing permission outranks an engine that is not ready")
    func permissionsComeFirst() {
        let page = DiagnosticsFixture.page(
            engines: EngineConfiguration(speech: .appleSpeech, transformerPreference: [.rules]),
            permissions: [.microphone: .denied])

        #expect(page.summary.text.hasPrefix("Microphone"))
    }

    /// Somebody who opens this page to be told nothing is wrong should be told, rather
    /// than left to check three sections themselves.
    @Test("says so plainly when there is nothing to do")
    func allClear() {
        let page = DiagnosticsFixture.page(permissions: [
            .microphone: .granted, .accessibility: .granted,
        ])

        #expect(!page.summary.needsAttention)
        #expect(page.summary.text == "Everything Uttrflow needs is in place.")
        #expect(page.summary.action == nil, "there is nothing to press")
    }

    /// An unchecked permission is not a broken one. Reporting "not checked yet" as a
    /// problem would put an amber banner on a page that has found nothing wrong.
    @Test("an unchecked permission is not a problem")
    func unknownIsNotAttention() {
        #expect(!DiagnosticsFixture.page().summary.needsAttention)
    }
}
