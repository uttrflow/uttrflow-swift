import Testing

@testable import UttrflowPredict

@Suite("Deciding whether an input method is composing")
struct CompositionTests {
    @Test(
        "A field that reports marked text settles it, whatever the input source is.",
        arguments: InputSourceKind.allCases)
    func markedTextWins(kind: InputSourceKind) {
        #expect(Composition.isComposing(markedText: .present, inputSource: kind))
    }

    @Test(
        "A field that reports no marked text settles it too, so an idle input method is not punished.",
        arguments: InputSourceKind.allCases)
    func absenceWins(kind: InputSourceKind) {
        #expect(!Composition.isComposing(markedText: .absent, inputSource: kind))
    }

    @Test("A silent field under a plain layout is not composing, because a layout cannot.")
    func silentFieldUnderLayout() {
        #expect(!Composition.isComposing(markedText: .unanswered, inputSource: .layout))
    }

    @Test(
        "A silent field under anything that can compose is assumed to be composing.",
        arguments: [InputSourceKind.inputMethod, .unknown])
    func silentFieldUnderInputMethod(kind: InputSourceKind) {
        #expect(Composition.isComposing(markedText: .unanswered, inputSource: kind))
    }

    @Test("Only a plain layout is incapable of composing.")
    func layoutAloneCannotCompose() {
        #expect(!InputSourceKind.layout.mayCompose)
        #expect(InputSourceKind.inputMethod.mayCompose)
        #expect(InputSourceKind.unknown.mayCompose)
    }
}
