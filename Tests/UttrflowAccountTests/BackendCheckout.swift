import Foundation
import Testing

/// Finds the private `uttrflow-backend` checkout, and says plainly when it is not there.
///
/// Four suites in this module judge the app against bytes the backend actually emits —
/// signed entitlement fixtures, the `/v1/me` document, the telemetry ingest schema. All
/// four are meaningless without it, and all four are expected to be skipped by anybody who
/// does not have it: the app repository is public and the backend is not.
///
/// **Skipping is fine. Skipping silently is not, and that is what this type is for.**
/// Each suite used to find the checkout by counting four `..` from `#filePath` and return
/// early when the fixture was missing. That reported a pass. A test that decodes JSON and
/// verifies an Ed25519 signature, passing in 0.001 seconds, is a test that did nothing.
///
/// It had already failed that way once, behind a hardcoded home directory, and it was
/// failing that way again when this was written — for a worse reason. `AGENTS.md` requires
/// every change to be made in a worktree under `.claude/worktrees/<name>`, and from there
/// four `..` lands on `.claude/worktrees`, which has no sibling backend. So the contract
/// suites were skipping for **every** change made the mandated way, and reporting eight
/// passes each time.
///
/// Hence searching upwards for the checkout rather than counting: the answer is the same
/// from the main checkout and from a worktree nested three levels inside it, and it does
/// not silently change the next time the tree is rearranged.
enum BackendCheckout {
    /// The checkout, or `nil` when it is genuinely not on this machine.
    static let root: URL? = locate()

    /// Whether the fixture-based contract suites can run at all.
    ///
    /// Read by `.enabled(if:)` on each of those suites, so an absent backend is reported
    /// as a skip by the test runner instead of being invisible.
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

    /// Walk up from this file looking for a directory that has `uttrflow-backend` in it.
    ///
    /// Bounded rather than unbounded: a search that runs to the filesystem root would
    /// happily find somebody else's checkout in a home directory and test against it.
    /// Twelve is far more than the deepest layout here (a worktree is seven up) and far
    /// less than the distance to `/`.
    private static func locate() -> URL? {
        // An explicit answer beats a search, and is the escape hatch for a layout nobody
        // anticipated. An override that points nowhere is `nil` rather than a silent
        // fallback to searching, because the whole failure being fixed here is a wrong
        // path that looked like an absent one.
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

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

/// A backend actually running somewhere, for the two suites that need one rather than a
/// fixture file.
///
/// Gated on `UTTRFLOW_BACKEND_URL` being set, and deliberately with no default. A default
/// of `127.0.0.1:8787` is what made the telemetry suite unskippable-looking: with nothing
/// listening there, its requests failed, it returned early, and it reported a pass — the
/// same silence this file exists to end. Requiring the variable makes running these a
/// decision somebody made rather than an accident of what was listening.
enum LiveBackend {
    /// The service to test against, or `nil` when nobody asked for one.
    static var url: URL? {
        guard let raw = ProcessInfo.processInfo.environment["UTTRFLOW_BACKEND_URL"],
            let url = URL(string: raw)
        else { return nil }
        return url
    }

    static var isConfigured: Bool { url != nil }

    static let absenceReason: Comment = """
        UTTRFLOW_BACKEND_URL is not set. These suites talk to a running backend. Start one \
        (cd ../uttrflow-backend && make run) and set the variable to reach it.
        """
}
