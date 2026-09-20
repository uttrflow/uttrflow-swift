// Tests that a notice closes the panel only when nothing is done in it meanwhile.

import Foundation
import Testing

@testable import Uttrflow

@MainActor
@Suite("Closing the panel after a notice")
struct NoticeLingerTests {
    @Test("with no further input the panel closes after the linger")
    func closesWhenLeftAlone() async throws {
        let linger = NoticeLinger(linger: .milliseconds(20))
        var closed = false
        linger.start { closed = true }
        try await Task.sleep(for: .milliseconds(200))
        #expect(closed)
        #expect(!linger.isPending)
    }

    @Test("a key pressed within the linger keeps the panel open past it")
    func aKeyKeepsItOpen() async throws {
        let linger = NoticeLinger(linger: .milliseconds(50))
        var closed = false
        linger.start { closed = true }
        try await Task.sleep(for: .milliseconds(10))
        linger.interrupt()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!closed)
    }

    @Test("a second notice restarts the wait rather than closing twice")
    func aSecondNoticeRestarts() async throws {
        let linger = NoticeLinger(linger: .milliseconds(20))
        var closes = 0
        linger.start { closes += 1 }
        linger.start { closes += 1 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(closes == 1)
    }
}
