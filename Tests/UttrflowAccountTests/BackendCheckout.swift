// Locates the private uttrflow-backend checkout and a running backend, so contract suites skip loudly.

import Foundation
import Testing

/// Finds the private `uttrflow-backend` checkout by searching upward, so its absence is a reported skip.
enum BackendCheckout {
    /// The checkout, or `nil` when it is genuinely not on this machine.
    static let root: URL? = locate()

    /// Read by `.enabled(if:)` on each contract suite, so an absent backend is a reported skip.
    static var isPresent: Bool { root != nil }

    /// A file under the checkout's `fixtures/`, or `nil` when there is no checkout.
    static func fixture(_ name: String) -> URL? {
        root?.appending(path: "fixtures/\(name)")
    }

    /// Explains, in the runner's output, why a suite did not run.
    static let absenceReason: Comment = """
        uttrflow-backend is not checked out beside this repository. These suites check the \
        app against fixtures that repository emits, so they cannot run without it. Clone it \
        as a sibling, or set UTTRFLOW_BACKEND_CHECKOUT to where it is.
        """

    /// Walks up at most twelve levels for `uttrflow-backend`; an unbounded search finds somebody else's.
    private static func locate() -> URL? {
        // An override pointing nowhere is `nil`, never a fallback to searching, so a wrong path looks wrong.
        if let override = ProcessInfo.processInfo.environment["UTTRFLOW_BACKEND_CHECKOUT"] {
            let url = URL(fileURLWithPath: override)
            return isDirectory(url) ? url : nil
        }

        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appending(path: "uttrflow-backend")
            if isDirectory(candidate) { return candidate }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }  // the filesystem root; there is no further up
            directory = parent
        }
        return nil
    }

    /// Whether `url` is an existing directory.
    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

/// A backend running at `UTTRFLOW_BACKEND_URL`, with no default so running these suites is a decision.
enum LiveBackend {
    /// The service to test against, or `nil` when nobody asked for one.
    static var url: URL? {
        guard let raw = ProcessInfo.processInfo.environment["UTTRFLOW_BACKEND_URL"],
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    static var isConfigured: Bool { url != nil }

    /// Explains, in the runner's output, why a suite did not run.
    static let absenceReason: Comment = """
        UTTRFLOW_BACKEND_URL is not set. These suites talk to a running backend. Start one \
        (cd ../uttrflow-backend && make run) and set the variable to reach it.
        """
}
