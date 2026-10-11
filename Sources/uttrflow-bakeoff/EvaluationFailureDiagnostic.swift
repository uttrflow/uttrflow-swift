import Foundation
import UttrflowCore
import UttrflowEval

/// Reports a thrown evaluation failure using only its case identifier and closed category.
enum EvaluationFailureDiagnostic {
    static func line(for testCase: EvaluationCase, category: ModelFailureClass) -> String {
        "\n  ! \(testCase.id): \(category.rawValue)\n"
    }

    static func write(_ testCase: EvaluationCase, category: ModelFailureClass) {
        FileHandle.standardError.write(Data(line(for: testCase, category: category).utf8))
    }
}
