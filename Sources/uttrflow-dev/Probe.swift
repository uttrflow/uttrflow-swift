import ArgumentParser
private import ApplicationServices
private import Foundation
private import UttrflowContext
private import UttrflowPredict

/// Phase 0's measurements: what fields will tell us, what retrieval costs, whether the tap works.
struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Measure what tab-to-complete can rely on, before any of it is built.",
        subcommands: [ProbeSurface.self, ProbeRetrieval.self, ProbeTap.self, ProbeIME.self]
    )
}

/// Sweeps the focused field of whichever app is in front, once a second.
struct ProbeSurface: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "surface",
        abstract: "Record what each app's focused field answers. Switch apps while it runs."
    )

    @Option(name: .long, help: "How long to sweep for, in seconds.")
    var seconds: Int = 60

    @Option(name: .long, help: "Where to write the markdown report.")
    var output: String?

    func run() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this binary, so every read would return nothing.")
            print("Grant it in System Settings › Privacy & Security › Accessibility, then re-run.")
            throw ExitCode.failure
        }

        print("Sweeping for \(seconds)s. Click into a text field in each app you want measured.\n")
        var sweep = CapabilitySweep()
        for tick in 0..<seconds {
            // Identity comes from the main thread, where NSWorkspace is safe to read.
            if let app = await MainActor.run(body: { FocusedFieldReader.frontmostApp() }),
                let reading = SurfaceProbe.read(of: app)
            {
                let known = sweep.readings.count
                sweep.record(reading)
                if sweep.readings.count > known {
                    print("  \(reading.application) · \(reading.role ?? "no role") · \(describe(reading))")
                }
            }
            if tick < seconds - 1 { try await Task.sleep(for: .seconds(1)) }
        }

        let markdown = ProbeReport(sweep).markdown()
        print("\n" + markdown)
        guard let output else { return }
        try markdown.write(toFile: output, atomically: true, encoding: .utf8)
        print("Written to \(output)")
    }

    private func describe(_ reading: SurfaceCapability) -> String {
        switch reading.placement {
        case .inlineGhost: "inline ghost"
        case .caretChip: "caret chip"
        case .windowStrip: "window strip"
        case nil: reading.isSecure ? "nothing — secure field" : "nothing — hides its text"
        }
    }
}

/// Times the two retrieval questions the design rests on, against a corpus this size.
struct ProbeRetrieval: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "retrieval",
        abstract: "Time exact-prefix and fuzzy matching, to check the plan's numbers on this Mac."
    )

    @Option(name: .long, help: "How many entries to measure against.")
    var entries: Int = 50_000

    func run() async throws {
        let corpus = RetrievalBenchmark.corpus(entries)
        print("\(corpus.count) entries\n")

        guard let index = RetrievalBenchmark.Index(corpus) else {
            print("  SQLite would not open a temporary database.")
            throw ExitCode.failure
        }
        defer { index.close() }

        let ranged = RetrievalBenchmark.time { index.rangeScan("git c", surface: 3) }
        let liked = RetrievalBenchmark.time { index.likeScan("git c", surface: 3) }
        print(String(format: "  SQLite range scan    %9.1f µs", ranged))
        print(String(format: "  SQLite LIKE          %9.1f µs   (%.0fx slower)", liked, liked / ranged))

        let loose = RetrievalBenchmark.time {
            RetrievalBenchmark.fuzzy("gti c", in: corpus, within: 1, prefiltered: false)
        }
        print(String(format: "  fuzzy, no prefilter  %9.1f µs", loose))
        for width in [6, 12] {
            let sized = RetrievalBenchmark.corpus(entries, maskWidth: width)
            let elapsed = RetrievalBenchmark.time {
                RetrievalBenchmark.fuzzy("gti c", in: sized, within: 1, prefiltered: true)
            }
            print(
                String(
                    format: "  prefilter, %2d-byte   %9.1f µs   (%.1fx faster)", width, elapsed,
                    loose / elapsed))
        }

        let exactHits = RetrievalBenchmark.exactPrefix("git p", in: corpus)
        let fuzzyHits = RetrievalBenchmark.fuzzy("git p", in: corpus, within: 1, prefiltered: true)
        print("\n  'git p' matches \(exactHits) exactly and \(fuzzyHits) within one edit.")
        print("  Fuzzy must therefore stay a fallback, never a parallel path.")
    }
}

/// Proves the event tap can take Tab conditionally, and can survive being disabled.
struct ProbeTap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tap",
        abstract: "Swallow Tab for a few seconds, then stop. Type into another app while it runs."
    )

    @Option(name: .long, help: "How long to hold the tap open, in seconds.")
    var seconds: Int = 20

    @Flag(name: .long, help: "Stall inside the callback, to force the system to disable the tap.")
    var stall = false

    func run() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this binary; an event tap cannot be created.")
            throw ExitCode.failure
        }
        let observer = TapObserver(stalling: stall)
        guard observer.start() else {
            print("The tap could not be created even though Accessibility is granted.")
            throw ExitCode.failure
        }
        print("Tab is being swallowed. Type in another app; press keys other than Tab too.\n")
        try await Task.sleep(for: .seconds(seconds))
        observer.stop()
        print(observer.summary())
    }
}

/// Watches whether the focused field will admit to an input method composing in it.
struct ProbeIME: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ime",
        abstract: "Report the marked-text range and the input source. See Docs/predict-ime.md."
    )

    @Option(name: .long, help: "How long to watch for, in seconds.")
    var seconds: Int = 60

    func run() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this binary, so every read would return nothing.")
            throw ExitCode.failure
        }

        print("Watching for \(seconds)s. Switch to an input method and type, so composition shows.\n")
        var previous = ""
        for tick in 0..<seconds {
            let app = await MainActor.run(body: { FocusedFieldReader.frontmostApp() })
            let marked = app.map { CompositionProbe.markedText(of: $0) } ?? .unanswered
            let source = await MainActor.run { CompositionProbe.refreshInputSourceKind() }
            let composing = Composition.isComposing(markedText: marked, inputSource: source)
            let line =
                "\(describe(marked)) · input source is a \(describe(source)) · composing=\(composing)"
            if line != previous {
                print("  \(line)")
                previous = line
            }
            if tick < seconds - 1 { try await Task.sleep(for: .seconds(1)) }
        }
    }

    private func describe(_ marked: MarkedText) -> String {
        switch marked {
        case .present: "the field reports marked text"
        case .absent: "the field reports no marked text"
        case .unanswered: "the field does not publish a marked range"
        }
    }

    private func describe(_ kind: InputSourceKind) -> String {
        switch kind {
        case .layout: "plain layout"
        case .inputMethod: "input method"
        case .unknown: "source that could not be read"
        }
    }
}
