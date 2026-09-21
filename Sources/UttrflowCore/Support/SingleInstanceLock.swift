// The lock that lets one copy of the app run per user, whatever path it was started from.

import Darwin
public import Foundation

/// An exclusive `flock` on one file, which the kernel releases when this is freed or the process ends.
public final class SingleInstanceLock: Sendable {
    /// What asking for the lock found.
    public enum Outcome: Sendable {
        /// This process holds the lock for as long as it keeps the value.
        case acquired(SingleInstanceLock)
        /// Another process holds it, so another copy of the app is running or still quitting.
        case heldElsewhere
        /// The file could not be opened or locked, carrying `errno`; the caller decides whether to run unguarded.
        case unavailable(Int32)
    }

    /// The open descriptor the lock lives on, internal so a test can read its flags.
    let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    // Closing the descriptor is what releases the lock, so nothing else is needed.
    deinit { close(descriptor) }

    /// The lock file for this build, in its own Application Support folder so a development build locks separately.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("instance.lock", in: directory)
    }

    /// Takes the lock at `file` without waiting, creating the file and its folder if needed.
    public static func acquire(at file: URL) -> Outcome {
        let folder = file.deletingLastPathComponent()
        do {
            try PrivateFile.makeDirectory(at: folder)
        } catch {
            return .unavailable(EIO)
        }
        // O_CLOEXEC, so a helper this process launches, such as the updater's installer, never inherits the lock.
        let descriptor = open(file.path(percentEncoded: false), O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return .unavailable(errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            return failure == EWOULDBLOCK ? .heldElsewhere : .unavailable(failure)
        }
        return .acquired(SingleInstanceLock(descriptor: descriptor))
    }

    /// Takes the lock at `file`, retrying while another process holds it until `timeout` has passed.
    public static func acquire(
        at file: URL, waitingUpTo timeout: Duration, pollingEvery interval: Duration = .milliseconds(50)
    )
        -> Outcome
    {
        let deadline = Date().addingTimeInterval(seconds(timeout))
        while true {
            let outcome = acquire(at: file)
            guard case .heldElsewhere = outcome, Date() < deadline else { return outcome }
            Thread.sleep(forTimeInterval: seconds(interval))
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
