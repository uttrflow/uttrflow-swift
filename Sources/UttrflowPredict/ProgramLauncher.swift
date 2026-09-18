public import Foundation

/// One run of a program a suggestion needs an answer from; it has no working directory, because none is chosen by the caller.
public struct ProgramLaunch: Sendable, Equatable {
    /// The absolute path of the program run.
    public let executable: String
    /// The arguments after the program's name.
    public let arguments: [String]
    /// The whole environment the program sees; nothing of this process's own is inherited.
    public let environment: [String: String]
    /// How long the program may take before it and everything it started is killed.
    public let timeout: Double

    /// A launch of `executable` with exactly these arguments and this environment.
    public init(executable: String, arguments: [String], environment: [String: String], timeout: Double) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
    }
}

/// Runs a program for its output; the seam a test replaces to see every launch without running anything.
public protocol ProgramLaunching: Sendable {
    /// The program's output when it exits 0 in time, `nil` for a failure, a timeout or too much output.
    func output(of launch: ProgramLaunch) async -> String?
}

/// Runs each program in its own process group, in a fresh empty directory, with its output read against the deadline.
public struct SpawnedProgramLauncher: ProgramLaunching {
    /// The most output one run may produce before it is killed; help pages are a few kilobytes.
    public static let defaultOutputLimit = 1 << 20

    /// How long one wait for output or exit lasts before the deadline is checked again, in milliseconds.
    static let pollMilliseconds: Int32 = 10

    /// The most bytes kept from one run.
    private let outputLimit: Int
    /// The clock the deadline is measured on, injected so a test decides when time is up.
    private let now: @Sendable () -> Date

    /// A launcher that keeps at most `outputLimit` bytes and reads time from `now`.
    public init(
        outputLimit: Int = SpawnedProgramLauncher.defaultOutputLimit,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.outputLimit = outputLimit
        self.now = now
    }

    /// Runs `launch` off the cooperative pool, since waiting on a child is blocking work.
    public func output(of launch: ProgramLaunch) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(launch))
            }
        }
    }

    /// Runs `launch` in a fresh empty directory that is removed afterwards.
    private func run(_ launch: ProgramLaunch) -> String? {
        guard let directory = Self.makeEmptyDirectory() else { return nil }
        defer { try? FileManager.default.removeItem(atPath: directory) }
        return run(launch, in: directory)
    }

    /// A new directory only this user can enter, empty, under the temporary directory.
    static func makeEmptyDirectory() -> String? {
        var template = Array((NSTemporaryDirectory() + "uttrflow-help.XXXXXX").utf8CString)
        return template.withUnsafeMutableBufferPointer { buffer -> String? in
            guard let base = buffer.baseAddress, mkdtemp(base) != nil else { return nil }
            return String(cString: base)
        }
    }

    /// Spawns the program as the leader of a new process group and collects what it writes until it exits or time is up.
    func run(_ launch: ProgramLaunch, in directory: String) -> String? {
        var ends: [Int32] = [-1, -1]
        guard pipe(&ends) == 0 else { return nil }
        let (reading, writing) = (ends[0], ends[1])
        guard let pid = Self.spawn(launch, in: directory, writingTo: writing) else {
            close(reading)
            close(writing)
            return nil
        }
        close(writing)
        defer { close(reading) }
        _ = fcntl(reading, F_SETFL, fcntl(reading, F_GETFL) | O_NONBLOCK)

        let deadline = now().addingTimeInterval(launch.timeout)
        var output = Data()
        var ended = false
        var exited = false
        while true {
            if !ended { ended = Self.drain(reading, into: &output, upTo: outputLimit) }
            if !exited { exited = Self.hasExited(pid) }
            if output.count > outputLimit || (!exited && now() >= deadline) {
                Self.killGroup(pid)
                return nil
            }
            // A program that exited is done even while something it started still holds the pipe.
            if exited {
                if !ended { _ = Self.drain(reading, into: &output, upTo: outputLimit) }
                break
            }
            Self.wait(for: ended ? nil : reading)
        }
        let status = Self.killGroup(pid)
        guard status == 0, output.count <= outputLimit else { return nil }
        return String(data: output, encoding: .utf8)
    }

    /// Spawns the program with stdin empty, stdout and stderr on `writing`, and every other descriptor closed.
    private static func spawn(
        _ launch: ProgramLaunch, in directory: String, writingTo writing: Int32
    ) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        // A child whose descriptors or directory could not be arranged is never started.
        let arranged = [
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, writing, 1),
            posix_spawn_file_actions_adddup2(&actions, writing, 2),
            posix_spawn_file_actions_addchdir(&actions, directory),
        ]
        guard arranged.allSatisfy({ $0 == 0 }) else { return nil }

        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setsigmask(&attributes, &unblocked)
        posix_spawnattr_setpgroup(&attributes, 0)
        let flags =
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))

        let argv = [launch.executable] + launch.arguments
        let envp = launch.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let spawned = withCStrings(argv) { argvPointers in
            withCStrings(envp) { envpPointers in
                posix_spawn(&pid, launch.executable, &actions, &attributes, argvPointers, envpPointers)
            }
        }
        return spawned == 0 ? pid : nil
    }

    /// Waits one poll interval, returning early when `reading` has something to read.
    private static func wait(for reading: Int32?) {
        guard let reading else {
            _ = poll(nil, 0, pollMilliseconds)
            return
        }
        var waiting = pollfd(fd: reading, events: Int16(POLLIN), revents: 0)
        _ = poll(&waiting, 1, pollMilliseconds)
    }

    /// Reads what is available now, stopping past `limit`; `true` once the pipe has no writer left.
    private static func drain(_ reading: Int32, into output: inout Data, upTo limit: Int) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while output.count <= limit {
            let count = buffer.withUnsafeMutableBytes { read(reading, $0.baseAddress, $0.count) }
            if count > 0 {
                output.append(contentsOf: buffer[0..<count])
                continue
            }
            return count == 0 || (errno != EAGAIN && errno != EINTR)
        }
        return false
    }

    /// Whether the leader has exited, leaving it unreaped so its process group cannot be reused before it is killed.
    private static func hasExited(_ pid: pid_t) -> Bool {
        var info = siginfo_t()
        return waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 && info.si_pid == pid
    }

    /// Kills everything left in the group, then reaps the leader and returns its exit status, or -1 when it did not exit normally.
    @discardableResult
    private static func killGroup(_ pid: pid_t) -> Int32 {
        kill(-pid, SIGKILL)
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        let signalled = status & 0x7F
        return signalled == 0 ? (status >> 8) & 0xFF : -1
    }
}

/// Calls `body` with a NULL-terminated C array of `strings`, valid only for the call.
private func withCStrings<Result>(
    _ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> Result
) -> Result {
    let pointers = strings.map { strdup($0) } + [nil]
    defer { pointers.forEach { free($0) } }
    return body(pointers)
}
