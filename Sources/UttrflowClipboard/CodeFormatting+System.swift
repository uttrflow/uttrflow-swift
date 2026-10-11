// Runs an installed formatter over a clip.

import Foundation
private import Darwin
public import UttrflowCore

/// Runs a real formatter from a fixed list of directories, on stdin, with no shell and a timeout.
public struct SystemCodeFormatter: CodeFormatting {
    /// Bounds formatter output to four times the largest accepted clip.
    static let maximumOutputBytes = ClipboardBudget.standard.largestClip * 4
    /// Gives a formatter a brief chance to exit after the deadline before killing it.
    static let terminationGrace: TimeInterval = 0.2

    /// Where a formatter is looked for; never `PATH`, which anything can prepend to.
    static let directories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/homebrew/opt/go/libexec/bin",
    ]

    public init() {}

    public func isAvailable(for language: CodeLanguage) async -> Bool {
        KnownFormatter(for: language).flatMap { executable(for: $0) } != nil
    }

    public func format(_ text: String, as language: CodeLanguage) async -> String? {
        guard let formatter = KnownFormatter(for: language),
            let tool = executable(for: formatter)
        else { return nil }

        return await run(tool, arguments: formatter.arguments(for: language), input: text)
    }

    /// The formatter's own file, or `nil` when it is not installed.
    private func executable(for formatter: KnownFormatter) -> URL? {
        for directory in Self.directories {
            let candidate = URL(filePath: directory).appending(path: formatter.rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// One bounded run with the code on standard input; `nil` on any refusal at all.
    private func run(_ tool: URL, arguments: [String], input: String) async -> String? {
        await Self.run(
            tool, arguments: arguments, input: input,
            environment: ["PATH": Self.directories.joined(separator: ":")], timeout: KnownFormatter.timeout)
    }

    /// Runs `tool` with nonblocking pipes, bounded output, and a kill escalation after `timeout`.
    static func run(
        _ tool: URL, arguments: [String], input: String, environment: [String: String],
        timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { continuation in
            // A queue of its own gets a thread at once, where a busy shared pool could start the run past its deadline.
            DispatchQueue(label: "com.uttrflow.clipboard.formatter-run", qos: .userInitiated).async {
                continuation.resume(
                    returning: runProcess(
                        tool, arguments: arguments, input: input,
                        environment: environment, timeout: timeout))
            }
        }
    }

    /// Pumps one subprocess without blocking on a pipe read or write; it blocks its caller until the run ends.
    static func runProcess(
        _ tool: URL, arguments: [String], input: String, environment: [String: String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // A bare environment: a clipboard panel's surroundings are not a project the user chose.
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let inputHandle = stdin.fileHandleForWriting
        let outputHandle = stdout.fileHandleForReading
        let errorHandle = stderr.fileHandleForReading
        let inputDescriptor = inputHandle.fileDescriptor
        let outputDescriptor = outputHandle.fileDescriptor
        let errorDescriptor = errorHandle.fileDescriptor
        let closeAllHandles = {
            for handle in [
                stdin.fileHandleForReading, inputHandle, stdout.fileHandleForWriting,
                outputHandle, stderr.fileHandleForWriting, errorHandle,
            ] {
                try? handle.close()
            }
        }

        guard
            setNonblocking(inputDescriptor), setNonblocking(outputDescriptor),
            setNonblocking(errorDescriptor)
        else {
            closeAllHandles()
            return nil
        }
        // A tool that stops reading makes the nonblocking write fail rather than raise SIGPIPE here.
        _ = fcntl(inputDescriptor, F_SETNOSIGPIPE, 1)
        do {
            try process.run()
        } catch {
            closeAllHandles()
            return nil
        }

        // Close the child's pipe ends in the parent so only the formatter controls EOF.
        try? stdin.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()

        var inputOpen = true
        var outputOpen = true
        var errorOpen = true
        defer {
            if inputOpen { try? inputHandle.close() }
            if outputOpen { try? outputHandle.close() }
            if errorOpen { try? errorHandle.close() }
        }

        let inputData = Data(input.utf8)
        var inputOffset = 0
        var outputData = Data()
        var outputExceededLimit = false
        var pipeFailed = false
        var deadlineExpired = false
        var terminationStarted: UInt64?
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let boundedTimeout = timeout.isFinite ? min(max(0, timeout), 60) : KnownFormatter.timeout
        let timeoutNanoseconds = UInt64(boundedTimeout * 1_000_000_000)
        let deadline = startedAt &+ timeoutNanoseconds
        let graceNanoseconds = UInt64(Self.terminationGrace * 1_000_000_000)

        func closeInput() {
            guard inputOpen else { return }
            try? inputHandle.close()
            inputOpen = false
        }

        func closeOutput() {
            guard outputOpen else { return }
            try? outputHandle.close()
            outputOpen = false
        }

        func closeError() {
            guard errorOpen else { return }
            try? errorHandle.close()
            errorOpen = false
        }

        func drain(
            _ descriptor: Int32, capturing: Bool, output: inout Data, budget: Int
        ) -> PipeDrainResult {
            var drained = 0
            while drained < budget {
                var buffer = [UInt8](repeating: 0, count: min(64 * 1_024, budget - drained))
                let amount = buffer.withUnsafeMutableBytes { bytes -> Int in
                    guard let address = bytes.baseAddress else { return 0 }
                    return Darwin.read(descriptor, address, bytes.count)
                }
                if amount > 0 {
                    if capturing {
                        guard output.count + amount <= Self.maximumOutputBytes else { return .overflow }
                        output.append(contentsOf: buffer.prefix(amount))
                    }
                    drained += amount
                    continue
                }
                if amount == 0 { return .closed }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return .drained }
                return .failed
            }
            return .drained
        }

        if inputData.isEmpty { closeInput() }
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            if terminationStarted == nil,
                (now >= deadline || outputExceededLimit || pipeFailed)
            {
                deadlineExpired = now >= deadline
                terminationStarted = now
                process.terminate()
            }
            if let terminationStarted,
                process.isRunning, now &- terminationStarted >= graceNanoseconds
            {
                _ = kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                break
            }
            if !process.isRunning {
                process.waitUntilExit()
                if outputOpen {
                    let result = drain(
                        outputDescriptor, capturing: true, output: &outputData, budget: 256 * 1_024)
                    if case .drained = result { pipeFailed = true }
                    apply(result, close: closeOutput, overflow: &outputExceededLimit, failed: &pipeFailed)
                    closeOutput()
                }
                if errorOpen {
                    let result = drain(
                        errorDescriptor, capturing: false, output: &outputData, budget: 256 * 1_024)
                    if case .drained = result { pipeFailed = true }
                    apply(result, close: closeError, overflow: &outputExceededLimit, failed: &pipeFailed)
                    closeError()
                }
                closeInput()
                break
            }

            let waitUntil = terminationStarted.map { $0 &+ graceNanoseconds } ?? deadline
            let remaining = waitUntil > now ? waitUntil &- now : 0
            let waitMilliseconds = Int32(min(50, max(1, (remaining + 999_999) / 1_000_000)))
            var descriptors: [pollfd] = []
            if inputOpen {
                descriptors.append(pollfd(fd: inputDescriptor, events: Int16(POLLOUT), revents: 0))
            }
            if outputOpen {
                descriptors.append(pollfd(fd: outputDescriptor, events: Int16(POLLIN), revents: 0))
            }
            if errorOpen {
                descriptors.append(pollfd(fd: errorDescriptor, events: Int16(POLLIN), revents: 0))
            }
            let result = descriptors.withUnsafeMutableBufferPointer { buffer in
                Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), waitMilliseconds)
            }
            if result < 0 {
                if errno != EINTR { pipeFailed = true }
                continue
            }

            for descriptor in descriptors where descriptor.revents != 0 {
                let events = descriptor.revents
                if descriptor.fd == inputDescriptor, inputOpen,
                    events & Int16(POLLOUT | POLLERR | POLLHUP | POLLNVAL) != 0
                {
                    let written = inputData.withUnsafeBytes { bytes -> Int in
                        guard let address = bytes.baseAddress else { return 0 }
                        return Darwin.write(
                            inputDescriptor, address.advanced(by: inputOffset),
                            min(bytes.count - inputOffset, 64 * 1_024))
                    }
                    if written > 0 {
                        inputOffset += written
                        if inputOffset == inputData.count { closeInput() }
                    } else if written < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                        continue
                    } else {
                        closeInput()
                    }
                } else if descriptor.fd == outputDescriptor, outputOpen,
                    events & Int16(POLLIN | POLLERR | POLLHUP | POLLNVAL) != 0
                {
                    apply(
                        drain(outputDescriptor, capturing: true, output: &outputData, budget: 256 * 1_024),
                        close: closeOutput, overflow: &outputExceededLimit, failed: &pipeFailed)
                } else if descriptor.fd == errorDescriptor, errorOpen,
                    events & Int16(POLLIN | POLLERR | POLLHUP | POLLNVAL) != 0
                {
                    apply(
                        drain(errorDescriptor, capturing: false, output: &outputData, budget: 256 * 1_024),
                        close: closeError, overflow: &outputExceededLimit, failed: &pipeFailed)
                }
            }
        }

        closeInput()
        closeOutput()
        closeError()
        guard
            !deadlineExpired, !outputExceededLimit, !pipeFailed,
            process.terminationStatus == 0, !outputData.isEmpty
        else { return nil }
        return String(data: outputData, encoding: .utf8)
    }
}

private enum PipeDrainResult {
    case drained
    case closed
    case overflow
    case failed
}

private func setNonblocking(_ descriptor: Int32) -> Bool {
    let flags = fcntl(descriptor, F_GETFL)
    return flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
}

private func apply(
    _ result: PipeDrainResult, close: () -> Void, overflow: inout Bool, failed: inout Bool
) {
    switch result {
    case .drained: break
    case .closed: close()
    case .overflow: overflow = true
    case .failed:
        failed = true
        close()
    }
}
