// Tests that classifying a large clip reads a bounded part of it with the costly patterns.

import Foundation
import Synchronization
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

/// Every fixture here is invented, and nothing in it is shaped like a credential.
extension HeavyClipScans {
    @Suite("Classifying a large clip reads a bounded part of it with the costly patterns", .serialized)
    struct ClipClassifyScalingTests {
        /// Everyday lines of each shape, none holding a vendor prefix or a run of thirteen digits.
        static let units: [String: String] = [
            "prose": "The clipboard keeps what you copied and shows it again when the panel opens. ",
            "logs":
                "2026-09-14T10:00:01.123Z INFO [worker-3] request id=48213 path=/api/items status=200 took=12ms\n",
            "csv": "1042,north river,Lakeside,4821.50,2026-09-14\n",
            "base64": "QmFzZTY0IGlzIGEgd2F5IHRvIHdyaXRlIGJ5dGVzIGFzIHRleHQgdGhhdCBzdXJ2aXZlcyBjb3B5aW5n\n",
            "hex dump": "0001f2a0: 4f2a 9c11 e0b3 77d2 0a6f 3c58 91be 2d44  O*....w..o<X..-D\n",
            "code": "    let total = values.reduce(0, +)\n",
            "minified": "function a(e,t){for(var n=0;n<e.length;n++)if(e[n]===t)return n;return-1};",
        ]

        /// The clip sizes above the sample threshold, up to the largest the watcher keeps.
        static let sizes = [256_000, 1_000_000, 2_000_000]

        static func clip(_ unit: String, bytes: Int) -> String {
            String(String(repeating: unit, count: bytes / unit.utf8.count + 1).utf8.prefix(bytes)) ?? unit
        }

        private static func codeShapeBytes(_ text: String) -> Int {
            let tally = ScanTally()
            CodeShapes.$tally.withValue(tally) { _ = CodeShapes.matches(text) }
            return tally.count
        }

        private static func patternCharacters(_ text: String) -> Int {
            let tally = ScanTally()
            SecretShapes.$patternTally.withValue(tally) { _ = SecretShapes.matches(text) }
            return tally.count
        }

        @Test(
            "The code-shape signals read no more than the sample, whatever the clip's size",
            arguments: units.keys.sorted())
        func codeShapesReadTheSample(shape: String) async throws {
            let unit = try #require(Self.units[shape])
            let read = await offTheTestPool {
                Self.sizes.map { Self.codeShapeBytes(Self.clip(unit, bytes: $0)) }
            }
            for (size, bytes) in zip(Self.sizes, read) {
                #expect(bytes <= CodeSample.longest, "\(shape): \(size) bytes read \(bytes)")
            }
        }

        @Test("A clip below the sample threshold is read whole")
        func smallClipsAreReadWhole() {
            let text = Self.clip("let total = values.reduce(0, +)\n", bytes: CodeSample.budget)
            #expect(Self.codeShapeBytes(text) == text.utf8.count)
            #expect(CodeSample.of(text) == text)
        }

        @Test("A one-megabyte unterminated CSS-like rule is sampled and classified in bounded time")
        func unterminatedCSSRuleIsBounded() async {
            let text = "#a {" + String(repeating: "b:c ", count: 249_999)
            let (matched, bytesRead, elapsed) = await offTheTestPool {
                let clock = ContinuousClock()
                let start = clock.now
                let tally = ScanTally()
                let matched = CodeShapes.$tally.withValue(tally) { CodeShapes.matches(text) }
                return (matched, tally.count, start.duration(to: clock.now))
            }

            #expect(text.utf8.count == 1_000_000)
            #expect(!matched)
            #expect(bytesRead <= CodeSample.longest)
            #expect(elapsed < .seconds(5), "classified one megabyte in \(elapsed)")
        }

        @Test(
            "A clip with no vendor prefix and no long digit run hands no characters to those patterns",
            arguments: units.keys.sorted())
        func cleanClipsSkipThePatterns(shape: String) async throws {
            let unit = try #require(Self.units[shape])
            let read = await offTheTestPool {
                Self.sizes.map { Self.patternCharacters(Self.clip(unit, bytes: $0)) }
            }
            #expect(read.allSatisfy { $0 == 0 }, "\(shape): \(read)")
        }

        @Test("Each vendor prefix and each long digit run costs the patterns a bounded window")
        func candidatesCostAWindow() async {
            // Three prefixes and one sixteen-digit run that fails Luhn, padded so a window is a small share of a line.
            let unit =
                "the task-list and the sk-docs mention AKIA once; order 4000 1234 5678 9011 shipped. "
                + String(repeating: "Nothing here is a key, only words that fill the line. ", count: 16)
                + "\n"
            let read = await offTheTestPool {
                Self.sizes.map { Self.patternCharacters(Self.clip(unit, bytes: $0)) }
            }
            for (size, characters) in zip(Self.sizes, read) {
                let lines = size / unit.utf8.count + 1
                #expect(
                    characters <= lines * (3 * VendorKeyWindows.width + 32), "\(size) bytes: \(characters)")
                #expect(characters < size / 4, "\(size) bytes: \(characters)")
            }
        }

        @Test(
            "Code at the start or the end of a large clip is read, and code only between the sampled windows is not"
        )
        func sampledWindows() {
            let prose = Self.clip(Self.units["prose"] ?? "", bytes: 1_000_000)
            let snippet = "\nfunc load() {\n    return data;\n}\n"
            #expect(ClipKindDetector.kind(of: snippet + prose) == .code)
            #expect(ClipKindDetector.kind(of: prose + snippet) == .code)
            // Between the first edge and the first middle window, which the sample does not read; see Docs/performance-idle.md.
            let at = prose.utf8.index(prose.utf8.startIndex, offsetBy: 40_000)
            let hidden = String(prose[..<at]) + snippet + String(prose[at...])
            #expect(!CodeSample.of(hidden).contains("func load"))
            #expect(ClipKindDetector.kind(of: hidden) == .text)
        }

        @Test("The sample keeps whole lines, and a clip with no line breaks is cut at character boundaries")
        func sampleShape() {
            let lines = Self.clip("é line of text\n", bytes: 300_000)
            let sample = CodeSample.of(lines)
            #expect(sample.utf8.count <= CodeSample.longest)
            #expect(sample.split(separator: "\n").allSatisfy { $0 == "é line of text" })
            let marks = String(repeating: "e\u{301}\u{302}", count: 100_000)
            let cut = CodeSample.of(marks)
            #expect(cut.utf8.count <= CodeSample.longest)
            #expect(cut.split(separator: "\n").allSatisfy { $0.allSatisfy { $0 == "e\u{301}\u{302}" } })
        }

        @Test(
            "Classification runs at utility priority, off the main thread, and answers with the language of code"
        )
        @MainActor
        func classifiesOffTheMainActor() async {
            let seen = Seen()
            let classified = await ClipKindDetector.classify("func load() {\n    return data;\n}") { text in
                seen.record(priority: Task.currentPriority, onMain: Thread.isMainThread)
                return ClipKindDetector.classification(of: text)
            }
            #expect(classified.kind == .code)
            #expect(seen.value?.priority == .utility)
            #expect(seen.value?.onMain == false)
            #expect(
                await ClipKindDetector.classify("hello there")
                    == ClipClassification(kind: .text, language: nil))
            #expect(
                await ClipKindDetector.classify(
                    "import Foundation\nlet x: Int = 1\nguard x > 0 else { return }"
                )
                .language == .swift)
        }
    }
}

/// Where a piece of work ran, recorded from whichever thread ran it.
private final class Seen: Sendable {
    private let state = Mutex<(priority: TaskPriority, onMain: Bool)?>(nil)

    var value: (priority: TaskPriority, onMain: Bool)? { state.withLock { $0 } }

    func record(priority: TaskPriority, onMain: Bool) { state.withLock { $0 = (priority, onMain) } }
}
