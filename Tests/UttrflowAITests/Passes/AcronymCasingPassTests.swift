import Testing
import UttrflowCore
import UttrflowDictionary

@testable import UttrflowAI

@Suite("AcronymCasingPass")
struct AcronymCasingPassTests {
    private let rules = CleaningPipeline.message(for: .standard(for: .plain), situation: .unknown)

    @Test(
        "writes an acronym said as one word in the lexicon's casing on the rules path",
        arguments: [
            ("the api returns json", "The API returns JSON."),
            ("api keys go in the sdk", "API keys go in the SDK."),
            ("we wrote three apis and two sdks", "We wrote three APIs and two SDKs."),
            ("the url, then the html.", "The URL, then the HTML."),
            ("store it as saas data in sql", "Store it as SaaS data in SQL."),
        ])
    func cased(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    /// The recogniser spells "https" and "ai" as one token, which makes them ordinary, but the lexicon spells them out.
    @Test("writes a spelt-out acronym whose letters spell an ordinary word in the lexicon's casing")
    func speltOutOrdinaryAcronym() {
        #expect(GeneralVocabulary.isOrdinary("https"))
        #expect(rules.run(Draft(text: "the ai answers over https")).text == "The AI answers over HTTPS.")
    }

    @Test(
        "leaves a common word that equals an acronym spelled lower case",
        arguments: [
            ("give it to us", "Give it to us."),
            ("the it team will rest", "The it team will rest."),
            ("add more ram to the arm", "Add more ram to the arm."),
        ])
    func ordinaryKept(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test("keeps a word written with its own casing")
    func ownCasingKept() {
        #expect(AcronymCasingPass().apply(Draft(text: "the aPi")).text == "the aPi")
        #expect(AcronymCasingPass().apply(Draft(text: "Api first")).text == "API first")
    }

    @Test("takes casing from acronyms on screen and leaves a dictionary word's case to the correction engine")
    func dictionaryAndScreen() {
        let screen = ["Ship the OKRz soon"]
        #expect(AcronymCasingPass(onScreen: screen).apply(Draft(text: "the okrz")).text == "the OKRz")
        let pass = AcronymCasingPass(vocabulary: ["KPIx", "okrz", "Zorbix"], onScreen: screen)
        #expect(
            pass.apply(Draft(text: "the kpix and okrz for zorbix")).text == "the kpix and okrz for zorbix")
    }

    @Test("takes an English word's screen casing only beside the same spoken neighbour")
    func englishWordNeedsNeighbour() {
        let pass = AcronymCasingPass(onScreen: ["SELECT id FROM orders;"])
        let prose = "select a seat from the front row"
        #expect(pass.apply(Draft(text: prose)).text == prose)
        #expect(pass.apply(Draft(text: "then select id from orders")).text == "then SELECT id FROM orders")
    }

    @Test(
        "writes a tool or language name in the lexicon's casing on the rules path",
        arguments: [
            ("we deploy on kubernetes with postgresql", "We deploy on Kubernetes with PostgreSQL."),
            ("port the javascript to typescript", "Port the JavaScript to TypeScript."),
            ("install numpy on linux", "Install NumPy on Linux."),
        ])
    func namedTools(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test("writes a language name without screen context when a version frame disambiguates it")
    func ordinaryLanguageNameInPlainText() {
        let draft = Draft(text: "we use python three")
        #expect(AcronymCasingPass(destination: .plain).apply(draft).text == "we use Python three")
        let standard = CleaningPipeline.standard(for: .standard(for: .plain), situation: .unknown)
        #expect(standard.run(draft).text == "We use Python three.")
        #expect(
            standard.run(Draft(text: "we feed python three thousand mice")).text
                == "We feed python 3000 mice.")
        #expect(
            AcronymCasingPass(destination: .plain, vocabulary: ["python"]).apply(draft).text
                == "we use python three")
        for destination in [Destination.codeEditor, .terminal] {
            let pass = AcronymCasingPass(destination: destination)
            #expect(pass.apply(draft).text == "we use Python three")
        }
    }

    @Test("leaves an ordinary word that a lexicon name is spelled like")
    func ordinaryNameKept() {
        #expect(rules.run(Draft(text: "let it go now")).text == "Let it go now.")
        let plain = AcronymCasingPass(destination: .plain)
        let standard = CleaningPipeline.standard(for: .standard(for: .plain), situation: .unknown)
        #expect(
            plain.apply(Draft(text: "a python swallowed a mouse")).text == "a python swallowed a mouse")
        #expect(
            plain.apply(Draft(text: "a python three feet long")).text == "a python three feet long")
        #expect(plain.apply(Draft(text: "we feed python three mice")).text == "we feed python three mice")
        #expect(plain.apply(Draft(text: "we use python three mice")).text == "we use python three mice")
        #expect(
            plain.apply(Draft(text: "we feed python three point five mice")).text
                == "we feed python three point five mice")
        #expect(
            plain.apply(Draft(text: "we feed python three thousand mice")).text
                == "we feed python three thousand mice")
        #expect(
            plain.apply(Draft(text: "we feed python three small mice")).text
                == "we feed python three small mice")
        #expect(
            standard.run(Draft(text: "we feed python three small mice")).text
                == "We feed python three small mice.")
        #expect(
            plain.apply(Draft(text: "we feed python three of the mice")).text
                == "we feed python three of the mice")
        #expect(
            standard.run(Draft(text: "we feed python three of the mice")).text
                == "We feed python three of the mice.")
        let editor = AcronymCasingPass(destination: .codeEditor)
        #expect(editor.apply(Draft(text: "we let go three")).text == "we let go three")
    }

    @Test("lets the user's dictionary spelling beat the lexicon's, at a sentence start too")
    func dictionaryBeatsLexicon() {
        let pass = AcronymCasingPass(vocabulary: ["postgresql"])
        #expect(pass.forms["postgresql"] == "postgresql")
        let pipeline = CleaningPipeline.message(
            for: .standard(for: .plain), situation: .unknown, vocabulary: ["postgresql"])
        #expect(pipeline.run(Draft(text: "postgresql is up")).text == "postgresql is up.")
    }

    @Test("keeps a lexicon name written in lower case at a sentence start")
    func lowerCaseNameAtStart() {
        #expect(AcronymCasingPass().lowerCaseForms["ripgrep"] == "ripgrep")
        #expect(rules.run(Draft(text: "it failed. ripgrep found it")).text == "It failed. ripgrep found it.")
    }

    @Test("reads only the acronyms that apply where the words are going")
    func destination() {
        #expect(AcronymCasingPass(destination: .terminal).forms["api"] == "API")
        #expect(AcronymCasingPass(destination: .plain).forms["python"] == nil)
        #expect(AcronymCasingPass().forms["go"] == nil)
    }

    @Test(
        "writes a spoken file name in the lexicon's casing, keeping the ending as spoken",
        arguments: [
            ("update the readme dot md first", "Update the README.md first."),
            ("add a line to the changelog dot md", "Add a line to the CHANGELOG.md."),
            ("open package dot json", "Open package.json."),
            ("rename it to app dot tsx", "Rename it to app.tsx."),
        ])
    func fileNameCased(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "writes a known file name or hardware acronym said as one bare word in the lexicon's casing",
        arguments: [
            ("aur readme mein naya flag", "Aur README mein naya flag."),
            ("plug it into the usb port", "Plug it into the USB port."),
        ])
    func bareFileStemAndHardwareCased(input: String, expected: String) {
        #expect(rules.run(Draft(text: input)).text == expected)
    }

    @Test("leaves a file stem that is an ordinary English noun in lower case when said bare")
    func bareOrdinaryFileStemKept() {
        #expect(
            rules.run(Draft(text: "the changelog lists two breaking changes")).text
                == "The changelog lists two breaking changes.")
    }

    @Test("takes a file name's casing from the screen or dictionary, else keeps it lower case")
    func fileNameFromScreen() {
        let pass = AcronymCasingPass(vocabulary: ["Podfile.lock"], onScreen: ["See AGENTS.md, then build."])
        #expect(
            pass.apply(Draft(text: "read agents.md and podfile.lock and notes.md")).text
                == "read AGENTS.md and Podfile.lock and notes.md")
        #expect(AcronymCasingPass().apply(Draft(text: "read agents.md")).text == "read agents.md")
    }

    @Test(
        "leaves an ordinary sentence with dot in it as words",
        arguments: ["she wore a polka dot dress", "connect the dot to the line"])
    func dotProseKept(input: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text.lowercased() == input + ".")
    }
}
