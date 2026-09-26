import Testing

@testable import UttrflowPredict

@Suite("A field's text colour")
struct TextColorTests {
    @Test("Black and white sit at the ends of the luminance scale, and their contrast is 21 to 1")
    func endsOfTheScale() {
        #expect(TextColor.black.luminance == 0)
        #expect(abs(TextColor.white.luminance - 1) < 1e-9)
        #expect(abs(TextColor.contrast(.black, .white) - 21) < 1e-9)
        #expect(TextColor.contrast(.white, .white) == 1)
    }

    @Test("A channel outside 0...1 is clamped, and one that is not a number is taken as 0")
    func channelsAreClamped() {
        let color = TextColor(red: 2, green: -1, blue: .nan)
        #expect(color == TextColor(red: 1, green: 0, blue: 0))
    }

    @Test("A dark channel is linear below the sRGB knee")
    func darkChannelIsLinear() {
        let dark = TextColor(red: 0.04, green: 0.04, blue: 0.04)
        #expect(abs(dark.luminance - 0.04 / 12.92) < 1e-9)
    }
}
