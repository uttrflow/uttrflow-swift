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

    @Test("takes casing from the dictionary and from acronyms written on screen")
    func dictionaryAndScreen() {
        let pass = AcronymCasingPass(vocabulary: ["KPIx", "Zorbix"], onScreen: ["Ship the OKRz soon"])
        #expect(
            pass.apply(Draft(text: "the kpix and okrz for zorbix")).text == "the KPIx and OKRz for Zorbix")
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

    @Test("leaves an ordinary word that a lexicon name is spelled like")
    func ordinaryNameKept() {
        #expect(rules.run(Draft(text: "let it go now")).text == "Let it go now.")
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
