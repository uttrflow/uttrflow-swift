// Opt-in crash and hang reports: when the reporter runs, what it is allowed to collect, and the scrubbing of each event.
import Foundation
public import Sentry

import struct Synchronization.Mutex

/// Starts and stops the crash reporter; a protocol so the switch is tested without a process-wide crash handler.
public protocol CrashReportingSDK: Sendable {
    /// Starts reporting with the options `configure` fills in.
    func start(_ configure: @escaping @Sendable (Options) -> Void)
    /// Stops reporting and uninstalls the crash handler.
    func close()
}

/// Follows the Settings switch; reports only while it is on and the build carries a DSN. See `Docs/crash-reporting.md`.
public final class CrashReporter: Sendable {
    /// The Info.plist key a release build's DSN is written under.
    public static let dsnKey = "SentryDSN"

    /// The DSN, or `nil` in a build that was not given one, which then never starts.
    public let dsn: String?
    /// `uttrflow@<version>+<build>`, or `nil` when the bundle does not say.
    public let release: String?
    /// Starts and stops the SDK.
    private let sdk: any CrashReportingSDK
    /// Told once for each event that survives scrubbing, which is each one that leaves this Mac.
    private let onSend: @Sendable () -> Void
    /// Whether the SDK is running.
    private let running = Mutex(false)

    /// Reads the DSN and release from `info`, which is the bundle's Info.plist.
    public init(
        info: [String: Any], sdk: any CrashReportingSDK, onSend: @escaping @Sendable () -> Void = {}
    ) {
        self.dsn = (info[Self.dsnKey] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.release = Self.release(in: info)
        self.sdk = sdk
        self.onSend = onSend
    }

    /// Whether reports are being collected.
    public var isRunning: Bool { running.withLock { $0 } }

    /// Starts when switched on in a build with a DSN, and closes when switched off.
    public func follow(isEnabled: Bool) {
        let change = running.withLock { running -> Bool? in
            let wanted = isEnabled && dsn != nil
            guard wanted != running else { return nil }
            running = wanted
            return wanted
        }
        guard let change else { return }
        if change, let dsn {
            let release = release
            let onSend = onSend
            sdk.start { Self.configure($0, dsn: dsn, release: release, onSend: onSend) }
        } else {
            sdk.close()
        }
    }

    /// The release name the dashboard groups by.
    static func release(in info: [String: Any]) -> String? {
        guard let version = info["CFBundleShortVersionString"] as? String,
            let build = info["CFBundleVersion"] as? String
        else { return nil }
        return "uttrflow@\(version)+\(build)"
    }

    /// Crashes and hangs only: no PII, no tracing, no breadcrumbs, and every event scrubbed before it leaves.
    public static func configure(
        _ options: Options, dsn: String, release: String?, onSend: @escaping @Sendable () -> Void = {}
    ) {
        options.dsn = dsn
        options.releaseName = release
        options.debug = false
        options.sendDefaultPii = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.maxBreadcrumbs = 0
        options.enableLogs = false
        options.enableMetricKit = false
        options.attachStacktrace = false
        options.enableCrashHandler = true
        options.enableAppHangTracking = true
        options.enableAutoSessionTracking = true
        options.beforeSend = { event in
            let scrubbed = scrub(event)
            if scrubbed != nil { onSend() }
            return scrubbed
        }
        options.beforeBreadcrumb = { _ in nil }
    }

    // MARK: - Scrubbing

    /// The app, OS and device-model context keys an event may keep; every other context is dropped.
    static let keptContext: [String: Set<String>] = [
        "os": ["name", "version", "build", "kernel_version"],
        "device": ["model", "model_id", "arch"],
        "app": ["app_version", "app_build", "app_identifier", "app_name", "build_type"],
    ]

    /// Hang kinds, whose value the SDK writes; a crash's value can carry a Swift trap's message, so it never leaves.
    static let sdkWrittenValues: Set<String> = ["AppHang", "app_hang"]

    /// The event with nothing that could name the user or the Mac, or `nil` when it is not a crash or hang.
    public static func scrub(_ event: Event) -> Event? {
        guard let exceptions = event.exceptions, !exceptions.isEmpty else { return nil }
        event.user = nil
        event.serverName = nil
        event.breadcrumbs = nil
        event.extra = nil
        event.tags = nil
        event.modules = nil
        event.request = nil
        event.message = nil
        event.error = nil
        event.context = event.context.map(scrubbedContext)
        for exception in exceptions {
            let kind = exception.mechanism?.type ?? ""
            exception.value = sdkWrittenValues.contains(kind) ? exception.value.map(strippingPaths) : nil
            exception.mechanism?.desc = nil
            exception.mechanism?.data = nil
            scrub(exception.stacktrace)
        }
        for thread in event.threads ?? [] { scrub(thread.stacktrace) }
        scrub(event.stacktrace)
        for image in event.debugMeta ?? [] { image.codeFile = image.codeFile.map(lastComponent) }
        return event
    }

    /// Each frame's file and image cut to their last component.
    private static func scrub(_ stacktrace: SentryStacktrace?) {
        for frame in stacktrace?.frames ?? [] {
            frame.fileName = frame.fileName.map(lastComponent)
            frame.package = frame.package.map(lastComponent)
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            frame.vars = nil
        }
    }

    /// Only the kept contexts, and only their kept keys.
    static func scrubbedContext(
        _ context: [String: [String: Any]]
    ) -> [String: [String: Any]] {
        var kept: [String: [String: Any]] = [:]
        for (name, values) in context {
            guard let keys = keptContext[name] else { continue }
            kept[name] = values.filter { keys.contains($0.key) }
        }
        return kept
    }

    /// The last path component, or `~` for a bare home folder, whose last component is the user name.
    static func lastComponent(_ path: String) -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = parts.last else { return path }
        if path.hasPrefix("/"), parts.count <= 2, ["Users", "home"].contains(parts.first) { return "~" }
        return String(last)
    }

    /// Every absolute or home-relative path in `text` cut to its last component.
    static func strippingPaths(_ text: String) -> String {
        text.replacing(/(?:file:\/\/)?~?\/[^\s'"(),;:<>\[\]{}]*/) { match in
            let path = String(match.output)
            let trimmed = path.hasPrefix("file://") ? String(path.dropFirst("file://".count)) : path
            return trimmed.hasPrefix("~") && trimmed.split(separator: "/").count <= 1
                ? "~" : lastComponent(trimmed)
        }
    }
}
