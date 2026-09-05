import Foundation
import Testing

@testable import UttrflowPredict

@Suite("Telling one field from another")
struct SurfaceTests {
    @Test("Two fields of the same role in one application are different surfaces.")
    func locatorSeparates() {
        let omnibox = Surface(
            bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "omnibox")
        let search = Surface(bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "search")
        #expect(omnibox != search)
    }

    @Test("The same field in two directories is two surfaces, because the answers differ.")
    func scopeSeparates() {
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        #expect(here != there)
    }

    @Test("The same field twice is one surface, and hashes as one.")
    func sameFieldIsOne() {
        let first = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
        let second = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }
}
