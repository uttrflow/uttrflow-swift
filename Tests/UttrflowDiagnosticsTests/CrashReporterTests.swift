// Tests for CrashReporter: when it starts, what it may collect, and that no path or name survives scrubbing.

import Foundation
import Sentry
import Synchronization
import Testing

@testable import UttrflowDiagnostics

/// Records starts and closes instead of touching the process.
private final class FakeSDK: CrashReportingSDK {
    /// What happened, in order.
    private let calls = Mutex<[String]>([])
    /// What the last start's options said.
    private let lastOptions = Mutex<Snapshot?>(nil)

    /// Every start and close, in order.
    var log: [String] { calls.withLock { $0 } }
    /// What the last start's options said.
    var options: Snapshot? { lastOptions.withLock { $0 } }

    /// The options that matter, read out so they can cross the lock.
    struct Snapshot: Sendable {
        let dsn: String?
        let releaseName: String?
        let sendDefaultPii, debug, autoBreadcrumbs, networkBreadcrumbs, failedRequests, autoTracing: Bool
        let crashHandler, appHangs, hasBeforeSend, dropsBreadcrumbs: Bool
        let tracesSampleRate: Double?
        let maxBreadcrumbs: UInt
    }

    /// Fills a fresh set of options and records the start.
    func start(_ configure: @escaping @Sendable (Options) -> Void) {
        let options = Options()
        configure(options)
        let snapshot = Snapshot(
            dsn: options.dsn, releaseName: options.releaseName, sendDefaultPii: options.sendDefaultPii,
            debug: options.debug, autoBreadcrumbs: options.enableAutoBreadcrumbTracking,
            networkBreadcrumbs: options.enableNetworkBreadcrumbs,
            failedRequests: options.enableCaptureFailedRequests,
            autoTracing: options.enableAutoPerformanceTracing, crashHandler: options.enableCrashHandler,
            appHangs: options.enableAppHangTracking, hasBeforeSend: options.beforeSend != nil,
            dropsBreadcrumbs: options.beforeBreadcrumb?(Breadcrumb()) == nil,
            tracesSampleRate: options.tracesSampleRate?.doubleValue, maxBreadcrumbs: options.maxBreadcrumbs)
        lastOptions.withLock { $0 = snapshot }
        calls.withLock { $0.append("start") }
    }

    /// Records the close.
    func close() { calls.withLock { $0.append("close") } }
}

/// A release build's Info.plist, with a placeholder DSN.
private func releaseInfo() -> [String: Any] {
    [
        "SentryDSN": " https://key@o0.ingest.example.invalid/1 ",
        "CFBundleShortVersionString": "26.0926.0",
        "CFBundleVersion": "412",
    ]
}

@Suite("When crash reports are collected")
struct CrashReporterSwitchTests {
    @Test("off by default: nothing starts until the switch is on")
    func startsOnlyWhenOn() {
        let sdk = FakeSDK()
        let reporter = CrashReporter(info: releaseInfo(), sdk: sdk)
        reporter.follow(isEnabled: false)
        #expect(sdk.log.isEmpty && !reporter.isRunning)
        reporter.follow(isEnabled: true)
        reporter.follow(isEnabled: true)
        #expect(sdk.log == ["start"] && reporter.isRunning)
        reporter.follow(isEnabled: false)
        reporter.follow(isEnabled: false)
        #expect(sdk.log == ["start", "close"] && !reporter.isRunning)
    }

    @Test("a build with no DSN, or an empty one, never starts", arguments: [nil, "", "   "] as [String?])
    func noDSNNoReporter(dsn: String?) {
        let sdk = FakeSDK()
        var info = releaseInfo()
        info["SentryDSN"] = dsn
        let reporter = CrashReporter(info: info, sdk: sdk)
        reporter.follow(isEnabled: true)
        #expect(reporter.dsn == nil && sdk.log.isEmpty && !reporter.isRunning)
    }

    @Test("starts with crash-only options: no PII, no tracing, no breadcrumbs, and the scrubber in place")
    func startsWithCrashOnlyOptions() throws {
        let sdk = FakeSDK()
        CrashReporter(info: releaseInfo(), sdk: sdk).follow(isEnabled: true)
        let options = try #require(sdk.options)
        #expect(options.dsn == "https://key@o0.ingest.example.invalid/1")
        #expect(options.releaseName == "uttrflow@26.0926.0+412")
        #expect(!options.sendDefaultPii && !options.debug)
        #expect(options.tracesSampleRate == 0)
        #expect(!options.autoBreadcrumbs && !options.networkBreadcrumbs)
        #expect(!options.failedRequests && !options.autoTracing)
        #expect(options.maxBreadcrumbs == 0)
        #expect(options.crashHandler && options.appHangs)
        #expect(options.hasBeforeSend && options.dropsBreadcrumbs)
    }

    @Test("names no release when the bundle does not say its version")
    func noReleaseWithoutAVersion() {
        #expect(CrashReporter(info: ["SentryDSN": "x"], sdk: FakeSDK()).release == nil)
    }
}

@Suite("Scrubbing a crash report")
struct CrashReporterScrubTests {
    /// The user name no report may carry.
    private static let userName = "someone"
    /// The host name no report may carry.
    private static let hostName = "someones-macbook.local"

    /// A frame whose file and image are paths in the user's home folder.
    private func frame() -> Frame {
        let frame = Frame()
        frame.fileName = "/Users/someone/src/Uttrflow/Sources/Thing.swift"
        frame.package = "/Users/someone/Applications/Uttrflow.app/Contents/MacOS/Uttrflow"
        frame.function = "Thing.run()"
        frame.contextLine = "let text = \"what someone said\""
        frame.instructionAddress = "0x0000000100001234"
        return frame
    }

    /// A crash event salted with the user's name, home folder and host name wherever Sentry has a string.
    private func event(mechanism: String) -> Event {
        let event = Event(level: .fatal)
        event.user = User(userId: Self.userName)
        event.serverName = Self.hostName
        event.message = SentryMessage(formatted: "dictated by someone")
        event.extra = ["path": "/Users/someone/Documents"]
        event.tags = ["host": Self.hostName]
        event.breadcrumbs = [Breadcrumb(level: .info, category: "ui.click")]
        event.context = [
            "device": ["model": "Mac14,2", "name": Self.hostName, "arch": "arm64"],
            "os": ["name": "macOS", "version": "26.0.1", "hostname": Self.hostName],
            "app": ["app_version": "26.0926.0", "device_app_hash": "abc", "app_name": "Uttrflow"],
            "culture": ["locale": "en_IN"],
        ]
        let exception = Exception(
            value:
                "EXC_BAD_ACCESS at /Users/someone/Library/Caches/x.db and file:///Users/someone/ and ~/Notes",
            type: "EXC_BAD_ACCESS")
        exception.mechanism = Mechanism(type: mechanism)
        exception.mechanism?.desc = "someone's text"
        exception.stacktrace = SentryStacktrace(frames: [frame()], registers: [:])
        event.exceptions = [exception]
        let thread = SentryThread(threadId: 0)
        thread.stacktrace = SentryStacktrace(frames: [frame()], registers: [:])
        event.threads = [thread]
        event.stacktrace = SentryStacktrace(frames: [frame()], registers: [:])
        let image = DebugMeta()
        image.codeFile = "/Users/someone/Applications/Uttrflow.app/Contents/MacOS/Uttrflow"
        image.debugID = "A1B2C3D4-0000-4000-8000-00000000ABCD"
        event.debugMeta = [image]
        return event
    }

    /// The event as it would be sent, as text.
    private func sent(_ event: Event) throws -> String {
        let scrubbed = try #require(CrashReporter.scrub(event))
        let data = try JSONSerialization.data(withJSONObject: scrubbed.serialize(), options: [.sortedKeys])
        return try #require(String(data: data, encoding: .utf8))
    }

    @Test(
        "no user, host name, home folder, message or breadcrumb survives", arguments: ["mach", "nsexception"])
    func nothingPersonalLeaves(mechanism: String) throws {
        let text = try sent(event(mechanism: mechanism))
        for word in [
            Self.userName, Self.hostName, "Users", "Documents", "Caches", "ui.click", "en_IN",
            "device_app_hash",
        ] {
            #expect(!text.contains(word), "\(word) left the Mac")
        }
    }

    @Test("keeps what symbolication and grouping need")
    func keepsTheStack() throws {
        let scrubbed = try #require(CrashReporter.scrub(event(mechanism: "mach")))
        let frame = try #require(scrubbed.exceptions?.first?.stacktrace?.frames.first)
        #expect(frame.fileName == "Thing.swift")
        #expect(frame.package == "Uttrflow")
        #expect(frame.function == "Thing.run()")
        #expect(frame.instructionAddress == "0x0000000100001234")
        #expect(frame.contextLine == nil)
        #expect(scrubbed.debugMeta?.first?.codeFile == "Uttrflow")
        #expect(scrubbed.debugMeta?.first?.debugID == "A1B2C3D4-0000-4000-8000-00000000ABCD")
        #expect(scrubbed.exceptions?.first?.type == "EXC_BAD_ACCESS")
        #expect(scrubbed.exceptions?.first?.mechanism?.type == "mach")
        #expect(scrubbed.context?["device"]?["model"] as? String == "Mac14,2")
        #expect(scrubbed.context?["os"]?["version"] as? String == "26.0.1")
        #expect(scrubbed.context?["app"]?["app_version"] as? String == "26.0926.0")
        #expect(Set(scrubbed.context?.keys.map { $0 } ?? []) == ["device", "os", "app"])
    }

    @Test("an exception written from app data loses its text")
    func appWrittenValuesGo() throws {
        let scrubbed = try #require(CrashReporter.scrub(event(mechanism: "nsexception")))
        #expect(scrubbed.exceptions?.first?.value == nil)
        #expect(scrubbed.exceptions?.first?.mechanism?.desc == nil)
    }

    /// The text Swift writes for a duplicate-key trap, holding an invented dictionary word.
    private static let trapMessage = "Fatal error: Duplicate values for key: 'zorblatquin'"

    @Test(
        "a Swift trap's message, which the SDK puts in the value, never leaves",
        arguments: ["mach", "signal"])
    func trapMessageGoes(mechanism: String) throws {
        let event = event(mechanism: mechanism)
        event.exceptions?.first?.value = Self.trapMessage
        #expect(!(try sent(event)).contains("zorblatquin"))
    }

    @Test("a Swift trap's message attached to the mechanism's data never leaves")
    func trapMessageInMechanismDataGoes() throws {
        let event = event(mechanism: "nsexception")
        event.exceptions?.first?.mechanism?.data = ["crash_info_messages": [Self.trapMessage]]
        #expect(!(try sent(event)).contains("zorblatquin"))
    }

    @Test("a hang keeps the value the SDK wrote for it")
    func hangValueStays() throws {
        let event = event(mechanism: "AppHang")
        event.exceptions?.first?.value = "App hanging for at least 2000 ms."
        let scrubbed = try #require(CrashReporter.scrub(event))
        #expect(scrubbed.exceptions?.first?.value == "App hanging for at least 2000 ms.")
    }

    @Test("an event that is not a crash or a hang is not sent")
    func onlyCrashesAndHangs() {
        #expect(CrashReporter.scrub(Event(level: .error)) == nil)
        let empty = Event(level: .error)
        empty.exceptions = []
        #expect(CrashReporter.scrub(empty) == nil)
    }

    @Test(
        "cuts a path to its last component, and a bare home folder to a tilde",
        arguments: [
            ("/Users/someone/Library/Helper", "Helper"),
            ("/Users/someone", "~"),
            ("/Users/someone/", "~"),
            ("/home/someone", "~"),
            ("Uttrflow", "Uttrflow"),
            ("/", "/"),
        ])
    func lastComponent(path: String, kept: String) {
        #expect(CrashReporter.lastComponent(path) == kept)
    }

    @Test("finds every path inside a sentence")
    func stripsPathsInText() {
        #expect(CrashReporter.strippingPaths("open /Users/someone/a.txt failed") == "open a.txt failed")
        #expect(CrashReporter.strippingPaths("(~/Secret/b.db)") == "(b.db)")
        #expect(CrashReporter.strippingPaths("at ~/ now") == "at ~ now")
        #expect(CrashReporter.strippingPaths("no paths here") == "no paths here")
    }
}
