import Foundation
import CoreGraphics
import Testing

@testable import UttrflowContext

/// One application's switches, recording every write it takes.
private final class FakeApplication {
    var values: [String: Bool]
    let supported: Set<String>
    var writes: [(String, Bool)] = []
    /// Whether a write that takes is still answered as a failure, as Chrome answers it.
    let reportsFailure: Bool

    init(values: [String: Bool] = [:], supported: Set<String>, reportsFailure: Bool = false) {
        self.values = values
        self.supported = supported
        self.reportsFailure = reportsFailure
    }

    var host: FullTreeSwitch.Host {
        FullTreeSwitch.Host(
            read: { self.supported.contains($0) ? self.values[$0] ?? false : nil },
            write: { attribute, isOn in
                self.writes.append((attribute, isOn))
                guard self.supported.contains(attribute) else { return false }
                self.values[attribute] = isOn
                return !self.reportsFailure
            })
    }
}

@Suite("Turning a browser engine's full Accessibility tree on and off")
struct FullTreeSwitchTests {
    @Test("An application on a bundled browser engine takes the manual switch.")
    func bundledEngineTakesTheManualSwitch() {
        let tree = FullTreeSwitch()
        let app = FakeApplication(supported: [FullTreeSwitch.manualAttribute])
        tree.switchOn(processIdentifier: 7, bundleIdentifier: "com.example.chat", host: app.host)
        #expect(app.values[FullTreeSwitch.manualAttribute] == true)
        #expect(tree.switchedOn == [7: FullTreeSwitch.manualAttribute])
    }

    @Test("Chrome, which ignores the manual switch, takes the screen reader's one.")
    func chromeTakesTheEnhancedSwitch() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "COM.GOOGLE.CHROME", host: chrome.host)
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(tree.switchedOn == [9: FullTreeSwitch.enhancedAttribute])
    }

    @Test("Chrome with the manual switch already on still gets the screen reader's one.")
    func chromeManualOnStillTakesTheEnhancedSwitch() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(
            values: [FullTreeSwitch.manualAttribute: true],
            supported: [FullTreeSwitch.manualAttribute, FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(tree.switchedOn == [9: FullTreeSwitch.enhancedAttribute])
    }

    @Test("A write that takes but is answered as a failure still counts, so it is turned off again.")
    func appliedWriteAnsweredAsFailureCounts() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute], reportsFailure: true)
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        #expect(tree.switchedOn == [9: FullTreeSwitch.enhancedAttribute])
        tree.switchOffEverything { _ in chrome.host }
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == false)
    }

    @Test("An application that is not a Chromium browser is never given the screen reader's switch.")
    func otherApplicationsKeepTheirWindowAnimations() {
        let tree = FullTreeSwitch()
        let native = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 3, bundleIdentifier: "com.example.notes", host: native.host)
        #expect(native.values[FullTreeSwitch.enhancedAttribute] == nil)
        #expect(tree.switchedOn.isEmpty)
    }

    @Test("A process is asked once, so a keystroke after the first costs no message.")
    func eachProcessIsAskedOnce() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        for _ in 0..<5 {
            tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        }
        #expect(chrome.writes.count == 2)
    }

    @Test("A tree something else turned on is left on when the loop stops.")
    func aTreeAlreadyOnIsNeverTurnedOff() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(
            values: [FullTreeSwitch.enhancedAttribute: true], supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        tree.switchOffEverything { _ in chrome.host }
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(chrome.writes.allSatisfy { $0.0 != FullTreeSwitch.enhancedAttribute })
    }

    @Test("An application change releases prior processes and preserves the active process")
    func appChangeReleasesOnlyPriorProcesses() {
        let tree = FullTreeSwitch()
        let previous = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        let active = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: previous.host)
        tree.switchOn(processIdentifier: 10, bundleIdentifier: "com.microsoft.edgemac", host: active.host)
        let oldGeneration = tree.generation

        tree.switchOffEverything(except: 10) { $0 == 9 ? previous.host : active.host }

        #expect(previous.values[FullTreeSwitch.enhancedAttribute] == false)
        #expect(active.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(tree.switchedOn == [10: FullTreeSwitch.enhancedAttribute])
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: previous.host,
            generation: oldGeneration)
        #expect(previous.values[FullTreeSwitch.enhancedAttribute] == false)
    }

    @Test("An older queued app cleanup cannot turn off a newer active tree")
    func staleQueuedAppCleanupIsSkipped() {
        let tree = FullTreeSwitch()
        let previous = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        let active = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: previous.host)
        let firstActivation = tree.invalidatePendingReads()
        let secondActivation = tree.invalidatePendingReads()
        tree.switchOn(
            processIdentifier: 11, bundleIdentifier: "com.google.Chrome", host: active.host,
            generation: secondActivation)

        tree.switchOffEverything(except: 10, generation: firstActivation) { _ in previous.host }
        #expect(previous.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(active.values[FullTreeSwitch.enhancedAttribute] == true)

        tree.switchOffEverything(except: 11, generation: secondActivation) { _ in
            previous.host
        }
        #expect(previous.values[FullTreeSwitch.enhancedAttribute] == false)
        #expect(active.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(tree.switchedOn == [11: FullTreeSwitch.enhancedAttribute])
    }

    @Test("A stop cleanup queued before restart cannot turn off the restarted tree")
    func restartInvalidatesQueuedStopCleanup() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        let stopGeneration = tree.invalidatePendingReads()

        let restartGeneration = tree.beginSession()
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host,
            generation: restartGeneration)
        let writesAfterRestart = chrome.writes.count

        tree.switchOffEverything(generation: stopGeneration) { _ in chrome.host }

        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == true)
        #expect(chrome.writes.count == writesAfterRestart)
        #expect(tree.switchedOn == [9: FullTreeSwitch.enhancedAttribute])
    }

    @Test("Stopping turns off what was turned on, and the next start asks again.")
    func stoppingTurnsItOffAndForgets() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(supported: [FullTreeSwitch.enhancedAttribute])
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        tree.switchOffEverything { _ in chrome.host }
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == false)
        #expect(tree.switchedOn.isEmpty)
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host)
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == true)
    }

    @Test("A field read finishing after stop cannot turn Chrome's full tree back on")
    func lateFieldReadCannotTurnTreeBackOnAfterStop() {
        let tree = FullTreeSwitch()
        let chrome = FakeApplication(
            values: [FullTreeSwitch.enhancedAttribute: false],
            supported: [FullTreeSwitch.enhancedAttribute])
        let readGeneration = tree.generation

        tree.switchOffEverything { _ in chrome.host }
        let writesAfterStop = chrome.writes.count
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host,
            generation: readGeneration)

        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == false)
        #expect(chrome.writes.count == writesAfterStop)
        #expect(tree.switchedOn.isEmpty)
    }

    @Test("Invalidating a full-tree read does not wait for its blocked Accessibility call")
    func invalidationDoesNotWaitForAccessibility() {
        let tree = FullTreeSwitch()
        let app = BlockingFullTreeApplication()
        let generation = tree.generation
        let readFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            tree.switchOn(
                processIdentifier: 7, bundleIdentifier: "com.example.chat", host: app.host,
                generation: generation)
            readFinished.signal()
        }
        #expect(app.readStarted.wait(timeout: .now() + .seconds(1)) == .success)

        let invalidationFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            tree.invalidatePendingReads()
            invalidationFinished.signal()
        }
        #expect(invalidationFinished.wait(timeout: .now() + .milliseconds(100)) == .success)
        #expect(tree.generation == generation + 1)

        app.resumeRead.signal()
        #expect(readFinished.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(!app.isOn)
    }

    @Test("A blocked read from an old session cannot settle the new session")
    func staleReadCannotSettleNewSession() {
        let tree = FullTreeSwitch()
        let app = BlockingFullTreeReadApplication()
        let oldGeneration = tree.generation
        let readFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            tree.switchOn(
                processIdentifier: 7, bundleIdentifier: "com.example.chat", host: app.host,
                generation: oldGeneration)
            readFinished.signal()
        }
        #expect(app.readStarted.wait(timeout: .now() + .seconds(1)) == .success)

        let newGeneration = tree.beginSession()
        app.resumeRead.signal()
        #expect(readFinished.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(tree.switchedOn.isEmpty)

        tree.switchOn(
            processIdentifier: 7, bundleIdentifier: "com.example.chat", host: app.host,
            generation: newGeneration)

        #expect(app.isOn)
        #expect(tree.switchedOn == [7: FullTreeSwitch.manualAttribute])
    }

    @Test("A blocked old-session write remains owned for stop cleanup")
    func staleWriteRemainsOwnedForCleanup() {
        let tree = FullTreeSwitch()
        let app = BlockingFullTreeWriteApplication()
        let oldGeneration = tree.generation
        let writeFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            tree.switchOn(
                processIdentifier: 7, bundleIdentifier: "com.example.chat", host: app.host,
                generation: oldGeneration)
            writeFinished.signal()
        }
        #expect(app.writeStarted.wait(timeout: .now() + .seconds(1)) == .success)

        tree.beginSession()
        app.resumeWrite.signal()
        #expect(writeFinished.wait(timeout: .now() + .seconds(1)) == .success)
        #expect(tree.switchedOn.isEmpty)
        #expect(app.isOn)

        tree.switchOffEverything { _ in app.host }

        #expect(!app.isOn)
        #expect(app.writes.contains { $0.0 == FullTreeSwitch.manualAttribute && !$0.1 })
    }

    @Test(
        "A Chromium browser is switched on whatever the read found, and elsewhere only a caretless text field is."
    )
    func whenTheTreeIsNeeded() {
        let reading = { (role: String, caret: CGRect?, secure: Bool) in
            FocusedFieldSnapshot(
                bundleIdentifier: "com.example.chat", applicationName: "Chat", role: role, value: "hi",
                caret: caret, isSecure: secure)
        }
        #expect(FullTreeSwitch.isNeeded(in: "com.google.Chrome", after: nil))
        #expect(FullTreeSwitch.isNeeded(in: "COM.GOOGLE.CHROME", after: nil))
        #expect(FullTreeSwitch.isNeeded(in: "com.example.chat", after: reading("AXTextArea", nil, false)))
        #expect(!FullTreeSwitch.isNeeded(in: "com.example.chat", after: nil))
        #expect(!FullTreeSwitch.isNeeded(in: "com.example.chat", after: reading("AXTextArea", .zero, false)))
        #expect(!FullTreeSwitch.isNeeded(in: "com.example.chat", after: reading("AXTextField", nil, true)))
        #expect(!FullTreeSwitch.isNeeded(in: "com.example.chat", after: reading("AXGroup", nil, false)))
    }

    @Test(
        "A write whose answer timed out still belongs to the switch, so a tree that came on later is turned off on stop"
    )
    func aTreeThatCameOnLateIsTurnedOff() {
        let tree = FullTreeSwitch()
        let chrome = SlowApplication()
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host, at: 0)
        #expect(tree.switchedOn.isEmpty)
        chrome.answering = true
        chrome.values[FullTreeSwitch.enhancedAttribute] = true
        tree.switchOffEverything { _ in chrome.host }
        #expect(chrome.values[FullTreeSwitch.enhancedAttribute] == false)
    }

    @Test("A process whose attempt got no answer is tried again after a while, a few times at most")
    func anUnansweredAttemptIsTriedAgain() {
        let tree = FullTreeSwitch()
        let chrome = SlowApplication()
        let wait = FullTreeSwitch.retryInNanoseconds
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host, at: 0)
        let first = chrome.writes.count
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host, at: wait - 1)
        #expect(chrome.writes.count == first)
        for attempt in 1..<(FullTreeSwitch.mostAttempts + 3) {
            tree.switchOn(
                processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host,
                at: UInt64(attempt) * wait)
        }
        #expect(chrome.writes.count == first * FullTreeSwitch.mostAttempts)
    }

    @Test("A retry that finds the tree on after its own earlier write settles it as this switch's")
    func aRetryFindingItsOwnWriteSettles() {
        let tree = FullTreeSwitch()
        let chrome = SlowApplication()
        tree.switchOn(processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host, at: 0)
        chrome.answering = true
        chrome.values[FullTreeSwitch.enhancedAttribute] = true
        let before = chrome.writes.count
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host,
            at: FullTreeSwitch.retryInNanoseconds)
        #expect(tree.switchedOn == [9: FullTreeSwitch.enhancedAttribute])
        #expect(chrome.writes.count == before + 1)
        tree.switchOn(
            processIdentifier: 9, bundleIdentifier: "com.google.Chrome", host: chrome.host,
            at: 10 * FullTreeSwitch.retryInNanoseconds)
        #expect(chrome.writes.count == before + 1)
    }
}

/// NSLock protects the fake switch state; semaphores coordinate its blocked read.
private final class BlockingFullTreeApplication: @unchecked Sendable {
    let readStarted = DispatchSemaphore(value: 0)
    let resumeRead = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var blocksFirstRead = true
    private var value = false

    var isOn: Bool { lock.withLock { value } }

    var host: FullTreeSwitch.Host {
        FullTreeSwitch.Host(
            read: { _ in
                let shouldBlock = self.lock.withLock {
                    defer { self.blocksFirstRead = false }
                    return self.blocksFirstRead
                }
                if shouldBlock {
                    self.readStarted.signal()
                    self.resumeRead.wait()
                }
                return self.lock.withLock { self.value }
            },
            write: { _, isOn in
                self.lock.withLock { self.value = isOn }
                return true
            })
    }
}

/// The first read blocks and then reports on; later reads expose the stored value.
private final class BlockingFullTreeReadApplication: @unchecked Sendable {
    let readStarted = DispatchSemaphore(value: 0)
    let resumeRead = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var readCount = 0
    private var value = false

    var isOn: Bool { lock.withLock { value } }

    var host: FullTreeSwitch.Host {
        FullTreeSwitch.Host(
            read: { _ in
                let readNumber = self.lock.withLock {
                    self.readCount += 1
                    return self.readCount
                }
                if readNumber == 1 {
                    self.readStarted.signal()
                    self.resumeRead.wait()
                    return true
                }
                return self.lock.withLock { self.value }
            },
            write: { _, isOn in
                self.lock.withLock { self.value = isOn }
                return true
            })
    }
}

/// The first write takes effect before blocking, so invalidation must retain its cleanup ownership.
private final class BlockingFullTreeWriteApplication: @unchecked Sendable {
    let writeStarted = DispatchSemaphore(value: 0)
    let resumeWrite = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var blocksFirstOnWrite = true
    private var value = false
    private var recordedWrites: [(String, Bool)] = []

    var isOn: Bool { lock.withLock { value } }
    var writes: [(String, Bool)] { lock.withLock { recordedWrites } }

    var host: FullTreeSwitch.Host {
        FullTreeSwitch.Host(
            read: { _ in self.lock.withLock { self.value } },
            write: { attribute, isOn in
                let shouldBlock = self.lock.withLock {
                    self.recordedWrites.append((attribute, isOn))
                    self.value = isOn
                    guard isOn, self.blocksFirstOnWrite else { return false }
                    self.blocksFirstOnWrite = false
                    return true
                }
                if shouldBlock {
                    self.writeStarted.signal()
                    self.resumeWrite.wait()
                }
                return true
            })
    }
}

/// A browser that answers no read in time and every write as not implemented, until told to answer.
private final class SlowApplication {
    var values: [String: Bool] = [:]
    var answering = false
    var writes: [(String, Bool)] = []

    var host: FullTreeSwitch.Host {
        FullTreeSwitch.Host(
            read: {
                self.answering && $0 == FullTreeSwitch.enhancedAttribute ? self.values[$0] ?? false : nil
            },
            write: { attribute, isOn in
                self.writes.append((attribute, isOn))
                if self.answering, attribute == FullTreeSwitch.enhancedAttribute {
                    self.values[attribute] = isOn
                }
                return false
            })
    }
}
