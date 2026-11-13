import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Naming cues: a spoken name request written in the file's own convention")
struct NamingCueTests {
    /// The piece passes at a code caret in `file`, with `preceding` before the caret.
    private func cleaned(_ spoken: String, in file: String, after preceding: String) -> String {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: file, precedingText: preceding)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let formatter = DestinationFormatter.standard(for: .codeEditor)
        let pipeline = CleaningPipeline.piece(
            numbers: formatter.numbers, digits: situation.digits(for: formatter),
            insertionPoint: situation.insertion, destination: .codeEditor, intent: situation.intent,
            screen: situation)
        return pipeline.run(Draft(text: spoken)).text
    }

    @Test("an empty file takes its language's default for each role, in six languages")
    func absentInSixLanguages() {
        let cases: [(String, String, String, String)] = [
            ("Example.swift", "let x = ", "getUserById", "UserProfile"),
            ("example.py", "x = ", "get_user_by_id", "UserProfile"),
            ("example.js", "const x = ", "getUserById", "UserProfile"),
            ("example.go", "x := ", "getUserById", "UserProfile"),
            ("example.rs", "let x = ", "get_user_by_id", "UserProfile"),
            ("Example.java", "int x = ", "getUserById", "UserProfile"),
        ]
        for (file, preceding, value, type) in cases {
            #expect(cleaned("name it get user by id", in: file, after: preceding) == value, "\(file) value")
            #expect(cleaned("type name user profile", in: file, after: preceding) == type, "\(file) type")
        }
        #expect(cleaned("constant name max retries", in: "example.rs", after: "let x = ") == "MAX_RETRIES")
    }

    @Test("the identifiers on screen are followed, in six languages")
    func presentInSixLanguages() {
        let cases: [(String, String, String)] = [
            ("Example.swift", "let orderTotals = fetchInvoices()\nlet x = ", "getUserById"),
            ("example.py", "order_totals = fetch_invoices()\nx = ", "get_user_by_id"),
            ("example.js", "const orderTotals = fetchInvoices();\nconst x = ", "getUserById"),
            ("example.go", "orderTotals := fetchInvoices()\nx := ", "getUserById"),
            ("example.rs", "let order_totals = fetch_invoices();\nlet x = ", "get_user_by_id"),
            ("Example.java", "int orderTotals = fetchInvoices();\nint x = ", "getUserById"),
        ]
        for (file, preceding, expected) in cases {
            #expect(
                cleaned("function name get user by id", in: file, after: preceding) == expected, "\(file)")
        }
    }

    @Test("a file that contradicts its language's default is followed")
    func contradicting() {
        #expect(
            cleaned(
                "variable name get user by id", in: "example.py", after: "orderTotals = fetchInvoices()\nx = "
            )
                == "getUserById")
        #expect(
            cleaned(
                "variable name get user by id", in: "Example.swift",
                after: "let order_totals = fetch_invoices()\nlet x = ")
                == "get_user_by_id")
    }

    @Test("the passes before the model read the file's convention too, so both paths write one name")
    func beforeModelFollowsTheFile() {
        let app = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "Example.swift", precedingText: "let order_totals = fetch_invoices()\nlet x = ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .codeEditor)
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .codeEditor), situation: situation)
        #expect(pipeline.run(Draft(text: "function name get user by id")).text == "get_user_by_id")
    }

    @Test("all caps said with the request writes the name in capitals joined by underscores")
    func allCapsAfterTheCue() {
        let camelFile = "let orderTotals = fetchInvoices()\nlet x = "
        #expect(cleaned("name it all caps user id", in: "Example.swift", after: camelFile) == "USER_ID")
    }

    @Test("a layout command ends the name and keeps its own effect")
    func layoutCommandEndsTheName() {
        let camelFile = "let orderTotals = fetchInvoices()\nlet x = "
        #expect(
            cleaned("name it user id new line name it order id", in: "Example.swift", after: camelFile)
                == "userId\norderId")
    }

    @Test("an opening mark before the name is kept")
    func openingMarkIsKept() {
        let camelFile = "let orderTotals = fetchInvoices()\nlet x = "
        #expect(cleaned("name it (user id)", in: "Example.swift", after: camelFile) == "(userId)")
    }

    @Test("an identifier already bound from the screen after the cue is the name, and the cue goes")
    func screenBoundIdentifierIsTheName() {
        let snakeFile = "user = get_user_by_id(1)\nx = "
        #expect(
            cleaned("function name get_user_by_id", in: "example.py", after: snakeFile) == "get_user_by_id")
    }

    @Test("a style said with the cue rewrites an identifier bound from the screen in that style")
    func explicitStyleRewritesABoundIdentifier() {
        let snakeFile = "user = get_user_by_id(1)\nx = "
        #expect(
            cleaned("name it camel case get_user_by_id", in: "example.py", after: snakeFile) == "getUserById")
    }

    @Test("a cue that ends its sentence names nothing, so the next sentence keeps its words")
    func cueEndingASentenceNamesNothing() {
        let pass = SpokenCasingPass(
            destination: .codeEditor, naming: .infer(from: .empty, language: .swift))
        #expect(pass.apply(Draft(text: "name it. user id")).text == "name it. user id")
        #expect(pass.apply(Draft(text: "name it user id")).text == "userId")
    }

    @Test("a casing command said with the request wins over the file's convention")
    func explicitStyleWins() {
        let camelFile = "let orderTotals = fetchInvoices()\nlet x = "
        #expect(
            cleaned("name it snake case get user by id", in: "Example.swift", after: camelFile)
                == "get_user_by_id")
        #expect(
            cleaned("snake case get user by id", in: "Example.swift", after: camelFile) == "get_user_by_id")
    }

    @Test(
        "without a request no word is renamed, and an unknown language with nothing on screen keeps the words"
    )
    func noRenamesUnasked() {
        let camelFile = "let orderTotals = fetchInvoices()\nlet x = "
        #expect(cleaned("get user by id", in: "Example.swift", after: camelFile) == "get user by id")
        #expect(cleaned("name it get user by id", in: "notes.txt", after: "x = ") == "name it get user by id")
    }

    @Test("the name ends at the clause: a spoken comma and the words after it are left alone")
    func endsAtClause() {
        #expect(
            cleaned("name it user id comma then explain it", in: "example.py", after: "x = ")
                == "user_id, then explain it")
    }

    @Test("a bare 'case' is the keyword, never a naming command")
    func bareCaseIsTheKeyword() {
        #expect(cleaned("case user id", in: "Example.swift", after: "switch x {\n") == "case user id")
    }

    @Test("in a comment the request is prose")
    func commentIsProse() {
        #expect(
            cleaned("name it get user by id", in: "Example.swift", after: "// ") == "name it get user by id")
    }
}
