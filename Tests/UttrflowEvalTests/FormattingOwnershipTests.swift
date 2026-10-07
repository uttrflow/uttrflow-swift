import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Each formatting class has one stated owner, and every pass it names is one the shipped pipelines run.
@Suite("Formatting-class ownership")
struct FormattingOwnershipTests {
    /// Every pass id a shipped pipeline runs, across every destination and a code editor outside a comment.
    static let shippedPasses: Set<PassID> = {
        var ids = Set<PassID>()
        for destination in Destination.allCases {
            let formatter = DestinationFormatter.standard(for: destination)
            ids.formUnion(CleaningPipeline.standard(for: formatter, situation: .unknown).ids)
            ids.formUnion(CleaningPipeline.afterModel(for: formatter, situation: .unknown).ids)
        }
        let code = CleaningPipeline.piece(
            numbers: DestinationFormatter.standard(for: .codeEditor).numbers,
            digits: DestinationFormatter.standard(for: .codeEditor).digits,
            destination: .codeEditor, documentName: "main.swift")
        ids.formUnion(code.ids)
        return ids
    }()

    @Test(
        "names at least one shipped pass for every class the rules own or share",
        arguments: FormattingClass.allCases)
    func rulesClassesNameShippedPasses(formattingClass: FormattingClass) {
        let ownership = formattingClass.ownership
        #expect((ownership.owner == .model) == ownership.passes.isEmpty, "\(formattingClass.rawValue)")
        for pass in ownership.passes {
            #expect(
                Self.shippedPasses.contains(pass),
                "\(formattingClass.rawValue) names \(pass), which no pipeline runs")
        }
    }

    @Test("gives every class a reason and at least one corpus case", arguments: FormattingClass.allCases)
    func everyClassHasReasonAndCase(formattingClass: FormattingClass) {
        #expect(!formattingClass.ownership.reason.isEmpty)
        #expect(
            (EvaluationCorpus.all + EvaluationCorpus.abstention).contains {
                $0.classes.contains(formattingClass)
            },
            "\(formattingClass.rawValue)")
    }

    @Test("fails a class that names a pass no pipeline runs")
    func unknownPassIsCaught() {
        #expect(!Self.shippedPasses.contains("noSuchPass"))
    }
}
