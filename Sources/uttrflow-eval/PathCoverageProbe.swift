// The `path-coverage` command: whether other voices' wrong forms for a term predict one more voice's.
import ArgumentParser
private import Foundation
private import UttrflowEval

/// Decodes a manifest of single-term clips and prints leave-one-speaker-out coverage of their wrong forms.
struct PathCoverageProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path-coverage",
        abstract: "Measure whether wrong forms harvested from other voices predict one more voice's.",
        discussion: """
            The manifest is the one `harvest-confusions` reads, with each clip one term read alone: \
            audio path, term, group, speaker. Each speaker is held out in turn.
            """
    )

    @Option(name: .long, help: "The tab-separated manifest of local single-term clips.")
    var manifest: String

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    func run() async throws {
        let (engine, utterances) = try await ManifestDecoder.decode(
            manifest: manifest, modelVariant: modelVariant)
        let coverage = SyntheticPathCoverage(utterances)
        let interval =
            coverage.covered.interval.map {
                String(format: "%.1f-%.1f%%", $0.lowerBound * 100, $0.upperBound * 100)
            } ?? "-"
        print("\(utterances.count) clips; \(engine)")
        print(
            "Covered: \(coverage.covered.hits) of \(coverage.covered.total) misheard (95% \(interval)); "
                + String(format: "%.1f paths per misheard term; ", coverage.pathsPerTerm)
                + "\(coverage.termsAlwaysRight) terms always right")
    }
}
