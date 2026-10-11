// The Latin output score beside recognition, with the instrument recorded on each row.
import UttrflowCore
import UttrflowEval

extension TranscribeCorpus {
    /// Prints the rate on the romanised text the user receives beside the recogniser's, per language.
    func printOutputRates(_ report: TranscriptionReport) {
        print("\nOutput word error rate (attested variants; recogniser rate in parentheses)")
        for language in TranscriptionCase.Language.allCases {
            let passages = report.scored.filter {
                $0.language == language && $0.outputWordErrorRate != nil
            }
            guard let output = report.outputWordErrorRate(in: language), !passages.isEmpty else {
                continue
            }
            let heard = WordErrorRate.combined(passages.compactMap(\.wordErrorRate))
            let instruments = Set(passages.map { $0.outputNormalisation ?? "legacy exact spelling" }).sorted()
            print(
                "  \(language.rawValue)  \(percent(output.rate))  (\(percent(heard.rate))) "
                    + "[\(instruments.joined(separator: ", "))]")
        }
    }
}
