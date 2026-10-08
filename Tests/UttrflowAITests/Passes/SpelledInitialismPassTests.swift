import Testing
@testable import UttrflowCore

@testable import UttrflowAI

@Suite("SpelledInitialismPass")
struct SpelledInitialismPassTests {
    private let sut = SpelledInitialismPass()

    @Test(
        "joins spoken letter names and writes common dotted abbreviations",
        arguments: [
            ("the a p i is down", "The API is down."),
            ("a p i is down", "API is down."),
            ("i e the main one", "I.e. the main one."),
            ("bring snacks e g chips", "Bring snacks e.g. chips."),
            ("we need it a s a p", "We need it ASAP."),
            ("open a p r for it", "Open APR for it."),
            ("a pen is here", "A pen is here."),
            ("so i think", "So I think."),
        ])
    func cleans(input: String, expected: String) {
        #expect(
            CleaningPipeline(passes: [sut, FirstWordPass(), TerminalStopPass()])
                .run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a lexicon form said with a joiner as one token",
        arguments: [
            ("we hold a q and a at four", "We hold a Q&A at four."),
            ("the field says n slash a", "The field says N/A."),
            ("sign here and slash or there", "Sign here and/or there."),
            ("r and d owns it", "R&D owns it."),
            ("send the p and l, please", "Send the P&L, please."),
            ("m and a work is slow", "M&A work is slow."),
            ("the i slash o is slow", "The I/O is slow."),
            ("ask him slash her", "Ask him/her."),
            ("he slash she will sign", "He/she will sign."),
            ("tea w slash o sugar", "Tea w/o sugar."),
            ("And slash or both", "And/or both."),
        ])
    func joinedForms(input: String, expected: String) {
        #expect(
            CleaningPipeline(passes: [sut, FirstWordPass(), TerminalStopPass()])
                .run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a joiner as a word where no form is said or the letters belong elsewhere",
        arguments: [
            "press the slash key",
            "slash and burn",
            "invite q and a few others",
            "we did q and a good one",
            "q and. a",
            "he slashed she said",
        ])
    func joinerKeptAsWord(input: String) {
        #expect(sut.apply(Draft(text: input)).text == input)
    }

    @Test("leaves r and d inside a longer spelled run to the letter runs")
    func joinerInsideSpelledRun() {
        #expect(sut.apply(Draft(text: "the x r and d y code")).text == "the XR and DY code")
    }

    @Test("leaves a stammered pronoun as two words rather than an initialism")
    func stammeredPronoun() {
        #expect(sut.apply(Draft(text: "I I think we should ship it")).text == "I I think we should ship it")
    }

    @Test(
        "never reads a cut-off word as a letter name",
        arguments: [
            ("I w- I went", "I w- I went"),
            ("so I t- to go", "so I t- to go"),
            ("I s- so", "I s- so"),
            ("I B M", "IBM"),
        ])
    func cutOff(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "joins a pair only when both are bare letters, and any run of three",
        arguments: [
            ("are o bhai sun", "are o bhai sun"),
            ("are be tum bhi", "are be tum bhi"),
            ("o be pagal hai kya", "o be pagal hai kya"),
            ("arre are o", "arre are o"),
            ("jay jay ho", "jay jay ho"),
            ("oh oh theek hai", "oh oh theek hai"),
            ("o ho", "o ho"),
            ("the p r is open", "the PR is open"),
            ("call the eff bee eye", "call the FBI"),
        ])
    func pairsNeedBareLetters(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "keeps a run made only of everyday words as words",
        arguments: [
            "you are coming tomorrow", "how are you", "i know you are busy", "see you later",
            "i see you tomorrow", "so you see it works", "oh i see", "oh why", "why you are late",
            "she asked me why i left early", "did you see the game", "be you",
        ])
    func everydayRun(input: String) {
        #expect(sut.apply(Draft(text: input)).text == input)
    }

    @Test(
        "joins unambiguous spelled runs",
        arguments: [("i b m", "IBM"), ("u s a", "USA")])
    func spelledRun(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "joins a doubled letter the stammer pass kept as spelling",
        arguments: [("a a one two three", "AA123"), ("b a a four", "BAA four"), ("i i t", "IIT")])
    func spelledDouble(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [StammersPass(), sut]).run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a stammered a or I in prose to the stammer pass",
        arguments: [
            ("I I think so", "I think so"), ("a a lot", "a lot"), ("we need a a plan", "we need a plan"),
        ])
    func proseDouble(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [StammersPass(), sut]).run(Draft(text: input)).text == expected)
    }

    @Test(
        "does not treat i adjacent to a letter name as the pronoun",
        arguments: [
            ("we said i e is the main one", "We said i.e. is the main one"),
            ("we said a p i is down", "We said API is down"),
        ])
    func adjacentI(input: String, expected: String) {
        let joined = sut.apply(Draft(text: input))
        let cased = FirstWordPass().apply(joined)
        #expect(WordShape.withoutTrailingStop(cased.text) == expected)
    }

    @Test(
        "does not join an article a to its following single letter",
        arguments: ["a p", "a pen", "we need a p", "we need a s a p"])
    func protectsArticle(input: String) {
        let result = CleaningPipeline(passes: [sut]).run(Draft(text: input)).text
        #expect(result == input)
    }

    @Test("distinguishes an article a from the letter name A at a sentence start")
    func articleAndInitialism() {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: "a p i")).text == "API")
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: "we need a p")).text == "we need a p")
    }

    @Test(
        "joins split AM only after a clock expression",
        arguments: [
            ("nine a m", "nine AM"),
            ("6:15 a m", "6:15 am"),
            ("five o'clock a m", "five o'clock AM"),
            ("we need a m", "we need a m"),
        ])
    func splitAMContext(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: input)).text == expected)
    }

    @Test(
        "ends a meridiem after a clock before the zone letters that follow it",
        arguments: [
            ("three p m e s t", "three PM EST"), ("10:30 a m p s t", "10:30 am PST"),
            ("5 p m g m t", "5 pm GMT"), ("nine a m c e t", "nine AM CET"),
            ("we need p m e s t", "we need PMEST"),
        ])
    func meridiemBeforeZone(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a meridiem after a clock time as am or pm, mid-sentence and at the end",
        arguments: [
            ("meet at 5 pm today", "meet at 5 pm today"), ("meet at 5 PM today", "meet at 5 pm today"),
            ("meet at 5 p.m. today", "meet at 5 pm today"), ("meet at 5 P.M. today", "meet at 5 pm today"),
            ("meet at 7:30 a.m. sharp", "meet at 7:30 am sharp"),
            ("meet at 7:30 a m sharp", "meet at 7:30 am sharp"),
            ("we meet at 5 pm", "we meet at 5 pm"), ("we meet at 5 PM.", "we meet at 5 pm."),
            ("we meet at 5 p.m.", "we meet at 5 pm"), ("we meet at 5 A.M.", "we meet at 5 am"),
            ("we left at 5 p.m. Then we ate.", "we left at 5 pm. Then we ate."),
            ("we left at 5 p.m., then ate", "we left at 5 pm, then ate"),
        ])
    func writesMeridiemHouseForm(input: String, expected: String) {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves am and pm that do not follow a clock time",
        arguments: ["i am here", "the PM said so", "a.m. radio", "at 25 pm"])
    func leavesNonMeridiem(input: String) {
        #expect(CleaningPipeline(passes: [sut]).run(Draft(text: input)).text == input)
    }

    @Test("does not join letters separated by a removed filler")
    func removedFillerBreaksInitialism() {
        var draft = Draft(text: "we said e uh g")
        draft.remove(at: 3, by: .fillers)
        #expect(sut.apply(draft).text == "we said e g")
    }

    @Test("does not treat i after a removed filler as part of the previous letter run")
    func removedFillerKeepsPronounI() {
        var draft = Draft(text: "we said p uh i")
        draft.remove(at: 3, by: .fillers)
        #expect(FirstWordPass().apply(draft).text == "We said p I")
    }

    @Test(
        "keeps the word are beside spelled letters and does not bridge it as R",
        arguments: [
            ("my a b c d are good", "My ABCD are good."),
            ("the letters are a b c d and e f g", "The letters are ABCD and EFG."),
            ("my initials are j r r tolkien", "My initials are JRR tolkien."),
            ("i have a b c d are you coming", "I have ABCD are you coming."),
        ])
    func keepsAreBesideSpelledRun(input: String, expected: String) {
        #expect(
            CleaningPipeline(passes: [sut, FirstWordPass(), TerminalStopPass()])
                .run(Draft(text: input)).text == expected)
    }
}

@Suite("SpelledInitialismPass in the shipped pipeline")
struct SpelledInitialismShippedTests {
    @Test(
        "keeps a dotted pair's stop, a clause-final letter a and the last letter's mark",
        arguments: [
            ("use a tool e g a hammer", "Use a tool e.g. a hammer."),
            ("use it i e now", "Use it i.e. now."),
            ("i live in the u s a", "I live in the USA."),
            ("i live in the u s a. we left", "I live in the USA. We left."),
            ("the a p i, then", "The API, then."),
            ("send the p d f a copy", "Send the PDF a copy."),
        ])
    func shipped(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a spelled unit after a number as the unit's own symbol",
        arguments: [
            ("start aspirin eighty one m g by mouth", "Start aspirin 81 mg by mouth."),
            ("give ten m l now", "Give 10 mL now."),
            ("pressure is ninety m m h g", "Pressure is 90 mmHg."),
            ("potassium twenty m e q", "Potassium 20 mEq."),
            ("weight seventy k g", "Weight 70 kg."),
            ("a 5 c m cut", "A 5 cm cut."),
            ("the 16 g b model", "The 16 GB model."),
            ("tune to 440 h z", "Tune to 440 Hz."),
            ("signal at 2.4 g h z", "Signal at 2.4 GHz."),
            ("the m g badge", "The MG badge."),
            ("the g b is full", "The GB is full."),
            ("ten x y z", "10 XYZ."),
        ])
    func unitSymbols(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a lexicon initialism with a spoken plural s as the initialism and a lower-case s",
        arguments: [
            ("track the k p i s", "Track the KPIs."),
            ("the a p i s are slow", "The APIs are slow."),
            ("review the p r s", "Review the PRs."),
            ("copy the u r l s", "Copy the URLs."),
            ("the c e o s met", "The CEOs met."),
            ("check the a w s bill", "Check the AWS bill."),
            ("the d n s record", "The DNS record."),
            ("write the c s s", "Write the CSS."),
            ("enable t l s", "Enable TLS."),
            ("which o s", "Which OS."),
            ("use h t t p s", "Use HTTPS."),
            ("the x y z s list", "The XYZS list."),
        ])
    func plurals(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test("every lexicon acronym not ending in s is read back as a plural from its spelled letters")
    func everyPlural() {
        let stems = LetterRun.acronyms.values.filter { stem in
            stem.allSatisfy { $0.isLetter } && LetterRun.acronyms[stem.lowercased() + "s"] == nil
        }
        #expect(stems.count >= 25)
        let wholeRuns = LetterRun.acronyms.keys.filter { $0.hasSuffix("s") && $0.count >= 3 }
        #expect(wholeRuns.count >= 10)
        for stem in stems {
            let spoken = (stem.lowercased() + "s").map(String.init).joined(separator: " ")
            #expect(LetterRun.pluralStem(of: spoken.split(separator: " ").map(String.init)) == stem)
        }
        for whole in wholeRuns {
            #expect(LetterRun.pluralStem(of: whole.map(String.init)) == nil, "\(whole)")
        }
    }

    @Test("every symbol in the table is read back from its spelled letters after a number")
    func everySymbol() {
        let symbols = Abbreviations.table.rows.compactMap(\.symbol)
        #expect(symbols.count >= 30)
        for symbol in symbols {
            let spoken = symbol.lowercased().map(String.init).joined(separator: " ")
            #expect(
                SpelledInitialismPass().apply(Draft(text: "take 5 \(spoken) now")).text
                    == "take 5 \(symbol) now")
        }
    }
}

@Suite("Spelled letters touching digits in the shipped pipeline")
struct SpelledCodeShippedTests {
    @Test(
        "writes letters then digits spoken as one code as one token",
        arguments: [
            ("the code is n one c four a g", "The code is N1C4AG."),
            ("post it to e c one a one b b", "Post it to EC1A1BB."),
            ("the code is k one a zero b one", "The code is K1A0B1."),
            ("the code is m five v three l nine", "The code is M5V3L9."),
            ("sit in seat b seven a", "Sit in seat B7A."),
            ("look at cell a one b two", "Look at cell A1B2."),
            ("tracking is z nine nine nine", "Tracking is Z999."),
            ("the flight is b a two eight three", "The flight is BA283."),
            ("order a b c one two three", "Order ABC123."),
            ("the part is x j two two zero", "The part is XJ220."),
            ("ship it on version v two point one", "Ship it on version v2.1."),
            ("we run v two point one point three", "We run v2.1.3."),
            ("build it for x two six four", "Build it for X264."),
            ("the model is r two d two", "The model is R2D2."),
            ("the room is g one two", "The room is G12."),
            ("the code is n w one two", "The code is NW12."),
            ("code w one a zero a x", "Code W1A0AX."),
            ("the file is q t three four", "The file is QT34."),
            ("the ticket is j k four five six", "The ticket is JK456."),
            ("the plate is l m five six", "The plate is LM56."),
        ])
    func joins(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a spelled lexicon initialism as the lexicon writes it, a final a included",
        arguments: [
            ("we talk over g r p c", "We talk over gRPC."),
            ("g r p c is fast", "gRPC is fast."),
            ("use m t l s only", "Use mTLS only."),
            ("ship the i o s build", "Ship the iOS build."),
            ("q a signed off an hour ago", "QA signed off an hour ago."),
            ("ask q a about it", "Ask QA about it."),
            ("the s l a covers it", "The SLA covers it."),
        ])
    func lexiconCasing(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a final a that opens a noun phrase, and letters the lexicon does not hold, as before",
        arguments: [
            ("press q a few times", "Press q a few times."),
            ("call i b m today", "Call IBM today."),
            ("the u s a team", "The US a team."),
            ("plan a or plan b", "Plan a or plan b."),
        ])
    func lexiconCasingKeeps(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves an article, a pronoun and a lone letter beside a number word as words",
        arguments: [
            ("it is a two hour drive", "It is a two hour drive."),
            ("i one day will go", "I one day will go."),
            ("b and c", "B and c."),
            ("i have a 3 day pass", "I have a 3 day pass."),
            ("plan a or plan b", "Plan a or plan b."),
            ("the 16 g b model", "The 16 GB model."),
            ("ten x y z", "10 XYZ."),
            ("the file is q five report", "The file is q five report."),
            ("build it for x eighty six", "Build it for x 86."),
            ("the u s two days later", "The US two days later."),
            ("take vitamin d three times", "Take vitamin d three times."),
            ("i lived in the u k for 2 years", "I lived in the UK for 2 years."),
            ("version two point one shipped", "Version 2.1 shipped."),
        ])
    func keeps(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }
}

@Suite("SpelledInitialismPass hex tokens")
struct SpelledInitialismHexTests {
    private let sut = SpelledInitialismPass()

    @Test(
        "joins characters after a hex cue into one lower-case token of an allowed length",
        arguments: [
            ("zero x f f", "0xff"),
            ("set it to zero x d e a d b e e f", "set it to 0xdeadbeef"),
            ("0 x 7 f", "0x7f"),
            ("hash f f five seven three three", "#ff5733"),
            ("hash f f 5 7 3 3", "#ff5733"),
            ("pound a b c", "#abc"),
            ("hash zero zero f f zero zero eight zero", "#00ff0080"),
            ("use hash f f f for the text", "use #fff for the text"),
            ("the colour is hash c zero c zero c zero.", "the colour is #c0c0c0."),
            ("revert commit a three f nine c two one", "revert commit a3f9c21"),
            ("the patch is commit a four c nine e one", "the patch is commit a4c9e1"),
            ("sha f f zero one", "sha ff01"),
            ("sha d e a d b e e f", "sha deadbeef"),
            ("hex f f zero zero", "hex ff00"),
            ("hex capital a b", "hex Ab"),
            (
                "commit" + String(repeating: " a b c d e f one two three four", count: 4),
                "commit" + " " + String(repeating: "abcdef1234", count: 4)
            ),
        ])
    func cued(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a run without a cue, or of a length the cue does not allow, as the letter join reads it",
        arguments: [
            ("a b c", "ABC"),
            ("hash browns for breakfast", "hash browns for breakfast"),
            ("dead beef is a meme", "dead beef is a meme"),
            ("hash f f", "hash FF"),
            ("hash f f f f", "hash FFFF"),
            ("commit a three f", "commit A3F"),
            ("hex a lot of it", "hex a lot of it"),
            ("zero x marks the spot", "zero x marks the spot"),
        ])
    func uncued(input: String, expected: String) {
        #expect(sut.apply(Draft(text: input)).text == expected)
    }
}
