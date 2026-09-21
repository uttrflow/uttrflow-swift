import Foundation
import Synchronization
import Testing

@testable import UttrflowPredict

/// A clock a test moves by hand.
private final class HandClock: Sendable {
    private let moment = Mutex(Date(timeIntervalSince1970: 1_800_000_000))

    var now: Date { moment.withLock { $0 } }

    func advance(by seconds: Double) { moment.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// A gate a blocked stat waits on until the test lets it go.
private final class Latch: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func wait() {
        semaphore.wait()
    }

    func release(_ count: Int) { for _ in 0..<count { semaphore.signal() } }
}

@Suite("Asking this Mac's disk without running anything")
struct SystemFileSystemTests {
    /// A directory holding a file, an executable, a folder and a link, removed when the test ends.
    private func laidOut() throws -> String {
        let root = FileManager.default.temporaryDirectory.appending(path: "disk-\(UUID().uuidString)")
            .path(percentEncoded: false).replacing(/\/$/, with: "")
        try FileManager.default.createDirectory(atPath: "\(root)/folder", withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: URL(filePath: "\(root)/file.txt"))
        try Data("#!/bin/sh\n".utf8).write(to: URL(filePath: "\(root)/tool"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(root)/tool")
        try FileManager.default.createSymbolicLink(
            atPath: "\(root)/link", withDestinationPath: "\(root)/folder")
        return root
    }

    @Test("A stat tells a folder, a file, an executable, a device and nothing apart, following links.")
    func kinds() throws {
        let root = try laidOut()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let disk = SystemFileSystem(environment: [:], homeDirectory: root)
        #expect(disk.kind(atPath: "\(root)/folder") == .directory)
        #expect(disk.kind(atPath: "\(root)/link") == .directory)
        #expect(disk.kind(atPath: "\(root)/file.txt") == .file(executable: false))
        #expect(disk.kind(atPath: "\(root)/tool") == .file(executable: true))
        #expect(disk.kind(atPath: "/dev/null") == .file(executable: false))
        #expect(disk.kind(atPath: "\(root)/missing") == .missing)
        #expect(disk.kind(atPath: "\(root)/file.txt/child") == .missing)
        #expect(disk.kind(atPath: "\(root)/" + String(repeating: "x", count: 4_000)) == .unknown)
        #expect(disk.homeDirectory == root)
    }

    @Test("A read and a listing are bounded, and refuse what is too large.")
    func boundedReads() throws {
        let root = try laidOut()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let disk = SystemFileSystem(environment: [:], homeDirectory: root)
        #expect(disk.contents(ofFile: "\(root)/file.txt", limit: 5) == "hello")
        #expect(disk.contents(ofFile: "\(root)/file.txt", limit: 4) == nil)
        #expect(disk.contents(ofFile: "\(root)/folder", limit: 100) == nil)
        #expect(disk.contents(ofFile: "/Volumes/Remote/file", limit: 100) == nil)
        #expect(disk.names(inDirectory: root, limit: 10)?.sorted() == ["file.txt", "folder", "link", "tool"])
        #expect(disk.names(inDirectory: root, limit: 3) == nil)
        #expect(disk.names(inDirectory: "/Volumes/Remote", limit: 10) == nil)
    }

    @Test(
        "The search path is the launch PATH, then /etc/paths, then the usual places, absolute and each once.")
    func searchPath() {
        let paths = SystemFileSystem.searchPaths(
            launch: "/usr/bin:relative::/bin", pathFiles: ["/usr/bin\n/sbin\n", " ~/tools \n"],
            home: "/Users/someone")
        #expect(Array(paths.prefix(4)) == ["/usr/bin", "/bin", "/sbin", "/Users/someone/tools"])
        #expect(paths.contains("/opt/homebrew/bin"))
        #expect(paths.contains("/Users/someone/.cargo/bin"))
        #expect(Set(paths).count == paths.count)
        let system = SystemFileSystem(environment: ["PATH": "/custom/bin"], homeDirectory: "/Users/someone")
        #expect(system.searchPaths.first == "/custom/bin")
    }

    @Test("Only a path under a volume that may be remote is given a deadline.")
    func remoteVolumes() {
        #expect(SystemFileSystem.remoteVolume(of: "/Volumes/Backup/x/y") == "/Volumes/Backup")
        #expect(SystemFileSystem.remoteVolume(of: "/Network/Servers") == "/Network/Servers")
        #expect(SystemFileSystem.remoteVolume(of: "/Volumes/") == nil)
        #expect(SystemFileSystem.remoteVolume(of: "/Users/someone") == nil)
    }

    @Test(
        "A remote stat that misses its deadline is unknown, and its volume is skipped until the time is up.")
    func slowVolume() {
        let clock = HandClock()
        let boxed = Mutex(0)
        let disk = SystemFileSystem(
            environment: [:], homeDirectory: "/h", probe: { _ in .directory },
            timeBox: { _, _ in
                boxed.withLock { $0 += 1 }
                return nil
            }, now: { clock.now })
        #expect(disk.kind(atPath: "/Volumes/Slow/a") == .unknown)
        #expect(disk.kind(atPath: "/Volumes/Slow/b") == .unknown)
        #expect(boxed.withLock { $0 } == 1)
        #expect(disk.kind(atPath: "/Users/a") == .directory)
        clock.advance(by: SystemFileSystem.slowVolumeLifetimeInSeconds + 1)
        #expect(disk.kind(atPath: "/Volumes/Slow/c") == .unknown)
        #expect(boxed.withLock { $0 } == 2)
        let answered = SystemFileSystem(
            environment: [:], homeDirectory: "/h", probe: { _ in .missing }, timeBox: { _, work in work() })
        #expect(answered.kind(atPath: "/Volumes/Quick/a") == .missing)
    }

    @Test("Work held to a time box that has not finished inside the budget is no answer.")
    func timeBox() {
        let latch = Latch()
        defer { latch.release(1) }
        let answer = SystemFileSystem.timeBoxed(within: .nanoseconds(0)) {
            latch.wait()
            return PathKind.missing
        }
        #expect(answer == nil)
    }

    @Test("A cached answer is believed for its lifetime and asked again after it.")
    func cache() {
        let clock = HandClock()
        let disk = FakeDisk(directories: ["/a"], texts: ["/a/t": "text"])
        let cached = CachedFileSystem(disk, now: { clock.now })
        #expect(cached.kind(atPath: "/a") == .directory)
        #expect(cached.kind(atPath: "/a") == .directory)
        #expect(cached.contents(ofFile: "/a/t", limit: 10) == "text")
        #expect(cached.contents(ofFile: "/a/t", limit: 10) == "text")
        #expect(disk.operations == [.stat("/a"), .read("/a/t")])
        clock.advance(by: CachedFileSystem.lifetimeInSeconds)
        _ = cached.kind(atPath: "/a")
        #expect(disk.operations.count == 3)
        #expect(cached.names(inDirectory: "/a", limit: 10) == ["t"])
        #expect(cached.homeDirectory == disk.homeDirectory)
        #expect(cached.searchPaths == disk.searchPaths)
        for index in 0...CachedFileSystem.capacity { _ = cached.kind(atPath: "/many/\(index)") }
        _ = cached.kind(atPath: "/a")
        #expect(disk.operations.last == .stat("/a"))
    }
}
