import Foundation
import Testing

/// Proves that the evaluation harness cannot reach the shipped app.
///
/// This is the structural half of a promise the product makes: the corpus is a thousand
/// recordings of real people in a private bucket, the operator token opens it, and none
/// of that may exist inside an app somebody installs. A convention — "nobody would import
/// that" — lasts until the first person who needs a word error rate in a diagnostics
/// pane. So it is asserted, here, where it fails in the same second it is broken.
///
/// The other half is in `Scripts/bundle.sh`, which reads the built artefact rather than
/// the sources: this suite proves that no source file asks for the harness, and that
/// proves that no compiled binary contains it.
@Suite("The harness stays out of the app")
struct EvaluationSeparationTests {
    /// The package root, found from this file rather than from the working directory,
    /// which is wherever the test runner happened to be started.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowEvalTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package
    }

    /// Everything that can end up inside `Uttrflow.app`: the app target and every module
    /// it links, directly or otherwise. The two measurement executables and the developer
    /// CLI are deliberately absent — they are the honest homes for this code.
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

    /// Belt and braces, and not redundant: the import check above proves nothing is used,
    /// and this proves nothing is *linked*. A dependency with no import still ships every
    /// symbol it defines into the binary.
    @Test("the app target does not depend on the harness in Package.swift")
    func theAppTargetDoesNotLinkTheHarness() throws {
        let manifest = try String(
            contentsOf: packageRoot.appending(path: "Package.swift"), encoding: .utf8)
        // Split on the target markers rather than trying to balance brackets: the markers
        // are stable, and a rearranged manifest should not break this.
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

    /// The corpus lives behind an operator token in a private bucket. Neither the token,
    /// the bucket, nor the endpoints that hand out signed URLs may be nameable from
    /// anything a user installs.
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

    /// The single `URLSession` this feature needs lives in the executable, not in the
    /// library, and it has to stay there: `UttrflowEval` is a library product, so anything
    /// that imported it would inherit whatever networking it contained.
    @Test("the harness library opens no connections of its own")
    func theHarnessLibraryHasNoNetworkCallSites() throws {
        // The same pattern `Scripts/offline_audit.sh` uses on the dictation path, applied
        // to the one module that could quietly widen it.
        let patterns = ["URLSession", "URLRequest", "NWConnection", "import Network", "https://"]
        var offenders: [String] = []
        for file in try swiftFiles(in: "UttrflowEval") {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Documentation may name a URL; code may not. Comments are stripped rather
            // than exempted by file, because an exemption by file is one somebody adds a
            // function to later.
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
