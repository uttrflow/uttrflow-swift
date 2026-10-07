import CoreGraphics
import Synchronization
import Testing

import UttrflowCore

@testable import UttrflowInput

@Suite("The feature ignores the keys it types itself")
struct SyntheticEventTests {
    /// Collects callback strokes without sharing a mutable array across a sendable closure.
    private final class StrokeRecorder: @unchecked Sendable {
        private let values = Mutex<[KeyEvent]>([])

        func append(_ stroke: KeyEvent) { values.withLock { $0.append(stroke) } }
        var strokes: [KeyEvent] { values.withLock { $0 } }
    }

    /// One key-down event, or nothing when the window server will not make one in this environment.
    private func keyDown(_ code: CGKeyCode) -> CGEvent? {
        CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: code, keyDown: true)
    }

    @Test("A tagged event is recognised as the app's own.")
    func taggedIsOurs() throws {
        let event = try #require(keyDown(48))
        SyntheticEvent.tag(event)
        #expect(SyntheticEvent.isOurs(event))
    }

    @Test("Event construction failure posts none of the batch.")
    func constructionFailurePostsNothing() {
        var built: [Int] = []
        var posted: [Int] = []

        #expect(throws: TextInsertionError.accessibilityDenied) {
            try buildThenPost(
                [1, 2, 3],
                build: { (value: Int) throws(TextInsertionError) -> Int in
                    built.append(value)
                    if value == 2 { throw .accessibilityDenied }
                    return value
                }, post: { posted.append(contentsOf: $0) })
        }

        #expect(built == [1, 2])
        #expect(posted.isEmpty)
    }

    @Test("An untagged event is treated as the user's, so real typing still wakes a turn.")
    func untaggedIsNotOurs() throws {
        let event = try #require(keyDown(48))
        #expect(!SyntheticEvent.isOurs(event))
    }

    @Test("Even a synthetic Tab, an accept key, is dropped, so acceptance can never feed itself.")
    func syntheticAcceptKeyIsDropped() throws {
        // 48 is Tab, the default accept key; tagging it is what the tap and monitor both drop on.
        let tab = try #require(keyDown(48))
        SyntheticEvent.tag(tab)
        #expect(SyntheticEvent.isOurs(tab))
    }

    @Test("Tagged key-down and flags-change events pass through without reaching the sink")
    func taggedEventsDoNotReachKeyboardSink() throws {
        let delivery = Delivery()
        let recorder = StrokeRecorder()
        delivery.set { recorder.append($0) }
        let userInfo = Unmanaged.passUnretained(delivery).toOpaque()
        let proxy = try #require(CGEventTapProxy(bitPattern: 1))

        let keyDownEvent = try #require(keyDown(12))
        SyntheticEvent.tag(keyDownEvent)
        _ = systemKeyboardCallback(
            proxy: proxy, type: .keyDown, event: keyDownEvent, userInfo: userInfo)

        let flagsChanged = try #require(keyDown(55))
        flagsChanged.flags = .maskCommand
        SyntheticEvent.tag(flagsChanged)
        _ = systemKeyboardCallback(
            proxy: proxy, type: .flagsChanged, event: flagsChanged, userInfo: userInfo)

        #expect(recorder.strokes.isEmpty)
    }

    @Test("An ordinary key-down still reaches the sink")
    func ordinaryEventsReachKeyboardSink() throws {
        let delivery = Delivery()
        let recorder = StrokeRecorder()
        delivery.set { recorder.append($0) }
        let userInfo = Unmanaged.passUnretained(delivery).toOpaque()
        let proxy = try #require(CGEventTapProxy(bitPattern: 1))
        let event = try #require(keyDown(12))

        _ = systemKeyboardCallback(proxy: proxy, type: .keyDown, event: event, userInfo: userInfo)

        #expect(recorder.strokes.count == 1)
        #expect(recorder.strokes.first?.phase == .down)
        #expect(recorder.strokes.first?.keyCode == 12)
    }
}
