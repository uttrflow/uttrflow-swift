import Testing
import UttrflowPredict

@testable import UttrflowLocalModel

/// A chat field with a screen and the person's own lines, which is where a made-up specific does harm.
private func chat(screen: String? = nil, own: [String] = [], choices: [String] = []) -> GenerationSituation {
    GenerationSituation(
        application: "Chat", field: "Message", surroundings: screen, recentLines: own, isMultiline: true,
        choices: choices)
}

/// A source file with code above the line, which reads as the code register.
private func code(own: [String] = []) -> GenerationSituation {
    GenerationSituation(
        application: "Editor", field: "Source", document: "Math.swift",
        preceding: "func add(a: Int, b: Int) -> Int {\n    return a + b\n}\n",
        recentLines: own + ["}", "    return a + b", "func add(a: Int, b: Int) -> Int {"], isMultiline: true)
}

/// A shell with commands above the line, which reads as the command register.
private func shell() -> GenerationSituation {
    GenerationSituation(
        application: "Terminal", field: "shell", document: "~/src/app", preceding: "$ git status",
        recentLines: ["git status", "ls -la ~/src", "cd ~/src/app && make -j"], isMultiline: true)
}

/// A query editor with a query above the line, which reads as the code register.
private func sql() -> GenerationSituation {
    GenerationSituation(
        application: "Editor", field: "SQL editor", document: "orders",
        preceding: "SELECT * FROM users LIMIT 10;",
        recentLines: ["SELECT * FROM users LIMIT 10;", "SELECT count(*) FROM orders;"], isMultiline: true)
}

@Suite("A model's line never adds a number, an amount or an address nobody gave it")
struct SpecificsTests {
    @Test(
        "A made-up specific is refused.",
        arguments: [
            ("Can we meet tomorrow at ", "Can we meet tomorrow at 3pm to go over it?"),
            ("The total comes to ", "The total comes to $120 before tax."),
            ("Call me on 98", "Call me on 9876543210"),
            ("Send it to ", "Send it to sam@example.com please"),
            ("The docs are at ", "The docs are at https://example.com/guide"),
            ("See github.com/", "See github.com/example/tool"),
            ("Pay at ", "Pay at acme-payments.com"),
            ("Growth was ", "Growth was 12% this quarter"),
            ("The meeting is on the ", "The meeting is on the 14th"),
            ("Fixed in ", "Fixed in #2041"),
        ])
    func madeUpSpecificsAreRefused(typed: String, line: String) {
        #expect(!Specifics.areGrounded(line, typed: typed, in: chat()))
        #expect(CompletionText.finished([line], typed: typed, in: chat()).isEmpty)
    }

    @Test(
        "Unprovided access keys are refused, whether their issuer uses digits or not.",
        arguments: [
            ("export API_KEY=", "export API_KEY=sk_live_a1b2c3d4e5f6"),
            ("export API_KEY=", "export API_KEY=ghp_abcdefghijklmnop"),
            ("export API_KEY=", "export API_KEY=sk-AbCdEfGhIjKlMnOp"),
        ])
    func madeUpCredentialIsRefused(typed: String, line: String) {
        #expect(!Specifics.areGrounded(line, typed: typed, in: code(), writesCode: true))
        #expect(CompletionText.finished([line], typed: typed, in: code()).isEmpty)
    }

    @Test("The output filter refuses credential shapes recognised by the shared scanner")
    func sharedCredentialShapesAreRefused() {
        let credentials = [
            ["xoxb", "2913847561", "3847561290", "KdMx8Qw2Lp"].joined(separator: "-"),
            ["glpat", "x7Kd9Pq2LmRt4Vw8Nz1C"].joined(separator: "-"),
            ["AKIA", "IOSFODNN7EXAMPLE"].joined(),
            ["eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "eyJzdWIiOiIxMjM0NTY3ODkwIn0", "sig"].joined(
                separator: "."),
            "-----BEGIN PRIVATE KEY-----",
        ]

        for credential in credentials {
            #expect(Specifics.namesCredential(credential), "\(credential.debugDescription)")
            let line = "export API_KEY=\(credential)"
            #expect(
                !Specifics.areGrounded(line, typed: "export API_KEY=", in: code(), writesCode: true),
                "\(credential.debugDescription)"
            )
        }
    }

    @Test("A specific copied from the screen, the person's lines, the typed text or the machine is kept.")
    func groundedSpecificsAreKept() {
        let line = "Can we meet tomorrow at 3pm to go over it?"
        let typed = "Can we meet tomorrow at "
        #expect(Specifics.areGrounded(line, typed: typed, in: chat(screen: "Priya: free at 3pm?")))
        #expect(Specifics.areGrounded(line, typed: typed, in: chat(own: ["3pm works"])))
        #expect(Specifics.areGrounded(line, typed: typed, in: chat(choices: ["3pm"])))
        #expect(
            Specifics.areGrounded(
                "Pay at acme-payments.com", typed: "Pay at ", in: chat(own: ["acme-payments.com"])))
        let knownCredential = "export API_KEY=sk_live_a1b2c3d4e5f6"
        #expect(
            Specifics.areGrounded(
                knownCredential, typed: "export API_KEY=", in: code(own: [knownCredential]), writesCode: true)
        )
        #expect(Specifics.areGrounded("Invoice 1,250 is paid", typed: "Invoice 1,250 ", in: chat()))
        #expect(
            !Specifics.areGrounded("Invoice 1,250.00 is paid", typed: "Invoice ", in: chat(own: ["1,250"])))
    }

    @Test("Words with no specific in them, and names that carry a digit, are left alone.")
    func ordinaryWordsAreLeftAlone() {
        #expect(Specifics.areGrounded("Sounds good, see you then", typed: "Sounds", in: chat()))
        #expect(Specifics.areGrounded("I use python3 for that", typed: "I use", in: chat()))
        #expect(Specifics.areGrounded("Open docs/guide.md first", typed: "Open", in: chat()))
        #expect(Specifics.areGrounded("Ping me @ noon", typed: "Ping", in: chat()))
        #expect(Specifics.specifics(in: "It costs 12.50", after: "It costs 12.50") == [])
    }

    @Test("Each shape of specific is recognised on its own.")
    func shapesAreRecognised() {
        for token in [
            "3pm", "12.50", "#12", "$5", "€20", "50%", "a@b", "http://x", "www.example.com", "example.com/a",
            "acme-payments.com", "sk_live_a1b2c3d4e5f6", "ghp_abcdefghijklmnop", "sk-AbCdEfGhIjKlMnOp",
        ] {
            #expect(Specifics.isSpecific(token), "\(token)")
        }
        for token in ["python3", "utf8", "hello", "docs/guide.md", "e.g", "@", "readme.md"] {
            #expect(!Specifics.isSpecific(token), "\(token)")
        }
    }

    @Test(
        "In code a literal that carries no value of its own is kept.",
        arguments: [
            ("0", "var co", "var count = 0"),
            ("0 with a semicolon", "let co", "let count = 0;"),
            ("1", "i ", "i += 1"),
            ("1 in an unrelated call", "let result = sum(", "let result = sum(1)"),
            (
                "1 in a later call argument", "let result = getUser(options, ",
                "let result = getUser(options, 1)"
            ),
            (
                "1 in a later entity-call argument", "let result = processUser(options, ",
                "let result = processUser(options, 1)"
            ),
            (
                "1 in a name that only starts with a lookup verb", "let result = forget(",
                "let result = forget(1)"
            ),
            ("1 in an ordinary call", "let result = process(", "let result = process(1)"),
            ("-1", "ret", "return -1"),
            ("0.0", "let off", "let offset = 0.0"),
            ("1.0", "view.al", "view.alpha = 1.0"),
            ("0 as an index", "let fi", "let first = items[0]"),
            ("0 as an index into ids", "let fi", "let first = ids[0]"),
            ("0 passed to a call", "let fi", "let first = items.remove(at: 0)"),
            ("1 as a call's argument", "sle", "sleep(1)"),
            ("0 as a bound", "for i", "for i in range(0, n):"),
            ("1 as a limit", "SELECT * FROM users ", "SELECT * FROM users LIMIT 1;"),
            ("1 taken from a count", "let last = ", "let last = count - 1"),
            ("true", "isRe", "isReady = true"),
            ("false", "isRe", "isReady = false"),
            ("nil", "var cache: Cache? ", "var cache: Cache? = nil"),
            ("null", "let us", "let user = null;"),
            ("None", "res", "result = None"),
            ("an empty string", "let na", "let name = \"\""),
            ("an empty quoted string", "na", "name = ''"),
            ("an empty list", "var it", "var items = []"),
            ("an empty object", "const op", "const options = {};"),
        ])
    func conventionalLiteralsAreKeptInCode(entry: String, typed: String, line: String) {
        #expect(Specifics.areGrounded(line, typed: typed, in: code(), writesCode: true), "\(entry)")
        #expect(CompletionText.finished([line], typed: typed, in: code()) == [line], "\(entry)")
    }

    @Test(
        "In code a literal that names a value nobody gave is refused.",
        arguments: [
            ("2", "let re", "let retries = 2"),
            ("10", "for i ", "for i in 0..<10 {"),
            ("0.5", "let ra", "let ratio = 0.5"),
            ("01", "let mo", "let month = 01"),
            ("1e9", "let li", "let limit = 1e9"),
            ("0x1f", "let ma", "let mask = 0x1f"),
            ("1_000", "let ca", "let cap = 1_000"),
            ("1 with a unit", "let de", "let delay = 1s"),
            ("0 and 2", "let pair = ", "let pair = (0, 2)"),
            ("an id of 1", "WHERE ", "WHERE id = 1;"),
            ("a key of 1", "WHERE ", "WHERE user_id = 1"),
            ("a camel-case key of 0", "fetch(", "fetch(userId: 0)"),
            ("a quoted key of 1", "{\"", "{\"id\": 1}"),
            (
                "an id passed to a finder", "let user = try await repo.findById(",
                "let user = try await repo.findById(1)"
            ),
            (
                "a user passed to a getter", "let user = try await repo.get",
                "let user = try await repo.getUser(1)"
            ),
            ("an order passed to a fetcher", "let order = repo.fetch", "let order = repo.fetchOrder(0)"),
            (
                "an account passed to a lookup", "let account = repo.lookupAccount(",
                "let account = repo.lookupAccount(0)"
            ),
            (
                "a record passed to an update", "let record = repo.updateRecord(",
                "let record = repo.updateRecord(0)"
            ),
            ("an id passed by name", "let order = orders.by", "let order = orders.byId(0)"),
            ("an id passed to a getter", "let name = get", "let name = getUserId(1)"),
            ("a quoted id passed to a finder", "find", "findById(\"1\")"),
            ("an id list", "WHERE ", "WHERE id IN (1)"),
            ("a key list", "WHERE user_id IN (0, ", "WHERE user_id IN (0, 1)"),
            ("an excluded key list", "WHERE user_id NOT IN (0, ", "WHERE user_id NOT IN (0, 1)"),
            ("a threshold of 0", "HAVING count", "HAVING count(o.id) > 0"),
            ("a threshold of 0 or more", "guard ", "guard a >= 0 else { return }"),
            ("a bound below 1", "if n ", "if n < 1 {"),
            ("an amount", "let fee = ", "let fee = $0"),
            ("a share", "let cut = ", "let cut = 0%"),
        ])
    func inventedLiteralsAreRefusedInCode(entry: String, typed: String, line: String) {
        #expect(!Specifics.areGrounded(line, typed: typed, in: code(), writesCode: true), "\(entry)")
        #expect(CompletionText.finished([line], typed: typed, in: code()).isEmpty, "\(entry)")
    }

    @Test(
        "A conventional number is refused as the first argument of a call naming a record entity",
        arguments: [
            "deleteUser", "deleteOrder", "deleteAccount", "deleteRecord", "deleteItem",
            "cancelUser", "cancelOrder", "cancelAccount", "cancelRecord", "cancelItem",
            "removeUser", "removeOrder", "removeAccount", "removeRecord", "removeItem",
            "lookupUser", "lookupOrder", "lookupAccount", "lookupRecord", "lookupItem",
            "updateUser", "updateOrder", "updateAccount", "updateRecord", "updateItem",
            "archiveUser", "archiveOrder", "archiveAccount", "archiveRecord", "archiveItem",
            "processUser", "user",
        ])
    func entityCallArgumentsAreRefused(_ call: String) {
        let typed = "let result = repository.\(call)("
        let line = "\(typed)1)"
        #expect(!Specifics.areGrounded(line, typed: typed, in: code(), writesCode: true), "\(call)")
        #expect(CompletionText.finished([line], typed: typed, in: code()).isEmpty, "\(call)")
    }

    @Test(
        "In a shell a number a command acts on is refused unless someone wrote it.",
        arguments: [
            ("a commit count", "git reset --hard HEAD", "git reset --hard HEAD~1"),
            ("a parent", "git show HEAD", "git show HEAD^1"),
            ("a process id", "kill ", "kill 1"),
            ("a line count", "tail -n ", "tail -n 1"),
            ("a count flag", "git log ", "git log -1"),
            ("a delay", "sle", "sleep 1"),
        ])
    func commandArgumentsAreRefused(entry: String, typed: String, line: String) {
        #expect(!Specifics.areGrounded(line, typed: typed, in: shell(), writesCode: true), "\(entry)")
        #expect(CompletionText.finished([line], typed: typed, in: shell()).isEmpty, "\(entry)")
    }

    @Test("In a shell a number someone wrote is kept.")
    func groundedCommandArgumentsAreKept() {
        let situation = GenerationSituation(
            application: "Terminal", field: "shell", preceding: "$ git log --oneline -1",
            recentLines: ["git status", "git reset --hard HEAD~1"], isMultiline: true)
        #expect(
            Specifics.areGrounded(
                "git reset --hard HEAD~1", typed: "git reset --hard", in: situation, writesCode: true))
    }

    @Test("A query keeps a conventional limit and refuses a made-up id.")
    func queriesKeepLimitsAndRefuseIds() {
        #expect(
            CompletionText.finished(["SELECT * FROM orders LIMIT 1;"], typed: "SELECT * FROM ord", in: sql())
                == [
                    "SELECT * FROM orders LIMIT 1;"
                ])
        #expect(CompletionText.finished(["WHERE id = 1042;"], typed: "WHERE ", in: sql()).isEmpty)
        #expect(CompletionText.finished(["WHERE id = 1;"], typed: "WHERE ", in: sql()).isEmpty)
    }

    @Test(
        "In prose even a conventional literal is a made-up number.",
        arguments: [
            ("Can we meet at ", "Can we meet at 1"), ("I have ", "I have 0 left"), ("Rated ", "Rated 1.0"),
        ])
    func conventionalLiteralsAreRefusedInProse(typed: String, line: String) {
        #expect(!Specifics.areGrounded(line, typed: typed, in: chat()))
        #expect(CompletionText.finished([line], typed: typed, in: chat()).isEmpty)
    }

    @Test("A name's words split at underscores and at each step into a capital.")
    func namesSplitIntoWords() {
        #expect(Specifics.words(of: "userId") == ["user", "id"])
        #expect(Specifics.words(of: "user_id") == ["user", "id"])
        #expect(Specifics.words(of: "ID") == ["id"])
        #expect(Specifics.words(of: "paid") == ["paid"])
    }
}
