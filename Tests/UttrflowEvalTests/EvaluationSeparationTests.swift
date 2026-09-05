// Proves the evaluation harness cannot reach the shipped app.
import Foundation
import Testing

/// Proves no source the app ships imports the harness; `Scripts/bundle.sh` checks the built artefact.
@Suite("The harness stays out of the app")
struct EvaluationSeparationTests {
    /// The package root, found from this file rather than from wherever the test runner started.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowEvalTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
    }

    /// Everything that can end up inside `Uttrflow.app`; the executables and the dev CLI stay out by design.
    private let shippedModules = [
        "Uttrflow", "UttrflowAI", "UttrflowAccount", "UttrflowAudio", "UttrflowContext", "UttrflowCore",
        "UttrflowDictionary", "UttrflowHistory", "UttrflowInput", "UttrflowPermissions",
        "UttrflowPipeline", "UttrflowSettings", "UttrflowSpeech", "UttrflowUX",
    ]

    private func swiftFiles(in module: String) throws -> [URL] {
        let directory = packageRoot.appending(path: "Sources/\(module)")
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("no module the app links imports the evaluation harness")
    func theAppDoesNotImportTheHarness() throws {
        var offenders: [String] = []
        for module in shippedModules {
            let files = try swiftFiles(in: module)
            #expect(!files.isEmpty, "Sources/\(module) has no Swift in it — has it been renamed?")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                if source.contains("import UttrflowEval") {
                    offenders.append(file.lastPathComponent)
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) imports UttrflowEval, which links the corpus \
            client into the shipped app. Move the measurement into uttrflow-eval.
            """)
    }

    /// A dependency with no import still ships every symbol into the binary, so linking is checked too.
    @Test("the app target does not depend on the harness in Package.swift")
    func theAppTargetDoesNotLinkTheHarness() throws {
        let manifest = try String(
            contentsOf: packageRoot.appending(path: "Package.swift"), encoding: .utf8)
        // Split on the target markers rather than balancing brackets, so a rearranged manifest still parses.
        let blocks =
            manifest.components(separatedBy: ".executableTarget(")
            + manifest.components(separatedBy: ".target(")
        let appBlock = blocks.first { $0.hasPrefix("\n            name: \"Uttrflow\",") }
        let block = try #require(appBlock, "no Uttrflow target found in Package.swift")
        let dependencies = String(block.prefix(while: { $0 != "]" }))
        #expect(
            !dependencies.contains("UttrflowEval"),
            "the Uttrflow app target now depends on UttrflowEval, so the harness ships to users")
    }

    /// Neither the token, the bucket, nor the signed-URL endpoints may be nameable from what a user installs.
    @Test("no module the app links names the corpus, its bucket or its token")
    func theAppNamesNothingAboutTheCorpus() throws {
        let forbidden = ["/v1/corpus", "UTTRFLOW_OPERATOR_TOKEN", "amazonaws.com", "uttrflow-corpus"]
        var offenders: [String] = []
        for module in shippedModules {
            for file in try swiftFiles(in: module) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for term in forbidden where source.contains(term) {
                    offenders.append("\(file.lastPathComponent): \(term)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.joined(separator: ", "))")
    }

    /// `UttrflowEval` is a library product, so any networking in it would be inherited by every importer.
    @Test("the harness library opens no connections of its own")
    func theHarnessLibraryHasNoNetworkCallSites() throws {
        // The same pattern `Scripts/offline_audit.sh` uses on the dictation path.
        let patterns = ["URLSession", "URLRequest", "NWConnection", "import Network", "https://"]
        var offenders: [String] = []
        for file in try swiftFiles(in: "UttrflowEval") {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Documentation may name a URL; code may not, so comments are stripped, not files exempted.
            let code = source.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for pattern in patterns where code.contains(pattern) {
                offenders.append("\(file.lastPathComponent): \(pattern)")
            }
        }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.joined(separator: ", ")) — UttrflowEval is a library product, so a \
            connection opened here can be inherited by anything that imports it. The one \
            transport belongs in Sources/uttrflow-eval.
            """)
    }
}
