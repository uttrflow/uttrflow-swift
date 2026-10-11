import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// A remote screen or a drawn canvas gives no caret text, so its words are formatted as for a field that will not say.
@Suite("Formatting where the focused element holds no text")
struct NoTextSurfaceFormattingTests {
    private static func cleaned(_ spoken: String, in app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation).run(Draft(text: spoken)).text
    }

    @Test(
        "capitalises the first word, adds no padding and keeps the stop policy of a field that will not say",
        arguments: ["send it over by friday", "okay", "the build is green now. ship it"])
    func formatsAsAnUnknownCaret(_ spoken: String) {
        let surface = AppContext(
            applicationName: "Viewer", bundleIdentifier: "com.example.viewer", unavailable: .notTextSurface)
        let unread = AppContext(applicationName: "Viewer", bundleIdentifier: "com.example.viewer")

        let written = Self.cleaned(spoken, in: surface)

        #expect(written == Self.cleaned(spoken, in: unread))
        #expect(written.first?.isUppercase == true)
        #expect(written.first?.isWhitespace == false)
    }
}
