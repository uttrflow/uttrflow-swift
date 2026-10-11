import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Layout commands precede contextual number conversion")
struct LayoutNumberOrderTests {
    @Test("layout does not promise independence from contextual number conversion")
    func declaresContextualOrder() {
        #expect(!LayoutWordsPass.orderIndependentWith.contains(.numberForms))
    }

    @Test(
        "shipped piece pipelines consume layout before interpreting numbers", arguments: Destination.allCases)
    func shippedOrder(_ destination: Destination) throws {
        let formatter = DestinationFormatter.standard(for: destination)
        let pipelines = [
            CleaningPipeline.standard(for: formatter, situation: .unknown),
            CleaningPipeline.beforeModel(for: formatter, situation: .unknown),
        ]
        for pipeline in pipelines {
            let layout = try #require(pipeline.ids.firstIndex(of: .layoutWords))
            let numbers = try #require(pipeline.ids.firstIndex(of: .numberForms))
            #expect(layout < numbers)
        }
    }

    @Test(
        "consumed commands do not leave a line-number cue",
        arguments: [
            ("new new line three .", "new\nthree .", "new\n3 ."),
            ("line three .", "line 3 .", "line 3 ."),
            ("new line three .", "new line 3 .", "new line 3 ."),
            ("new paragraph three .", "new paragraph three .", "new paragraph three ."),
        ])
    func contextualReading(_ input: String, _ layoutFirst: String, _ numbersFirst: String) {
        let draft = Draft(text: input)
        let layout = LayoutWordsPass()
        let numbers = NumberFormsPass()
        #expect(numbers.apply(layout.apply(draft)).text == layoutFirst)
        #expect(layout.apply(numbers.apply(draft)).text == numbersFirst)
    }
}
