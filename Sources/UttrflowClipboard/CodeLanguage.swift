import Foundation

/// Which language a code clip is written in, when that can be told from the clip alone.
///
/// Two things hang off this and both are decoration: a chip in the row, and colour in the
/// preview. Neither is worth being wrong about. A clip labelled `python` that is actually
/// Ruby is a small lie the user has to notice and discount every time they scan the list,
/// whereas an unlabelled clip is merely a clip — which is what every clip looked like
/// yesterday. So the set below is deliberately narrow, and ``detect(_:)`` answers `nil`
/// far more readily than it answers a case.
///
/// The languages that are here are here for one of two reasons: they are common enough in
/// a clipboard to be worth a chip, or they exist to keep another one honest. Go and Rust
/// are in the second group — both have a function keyword that a Swift-only detector
/// would have happily misread as Swift, and the cheapest way to stop that is to let them
/// compete.
public enum CodeLanguage: String, Sendable, Equatable, CaseIterable, Codable {
    case swift
    case python
    case ruby
    case javascript
    case typescript
    case json
    case sql
    case shell
    case html
    case css
    case go
    case rust
    case java

    /// The short form for a row chip, where three or four characters is all the width there
    /// is. Only the three names that are habitually abbreviated get one; everything else is
    /// already short enough that shortening it further would just be a puzzle.
    public var chip: String {
        switch self {
        case .javascript: "js"
        case .typescript: "ts"
        case .shell: "sh"
        default: rawValue
        }
    }
}

extension CodeLanguage {
    /// What language this text is written in, or nothing.
    ///
    /// Pure, synchronous and offline, like every other detector on this path. It runs once
    /// per clip on the copy path, so it cannot wait for anything — and the panel's whole
    /// promise is that it opens instantly. A language model would classify this better than
    /// the rules below do, and that is a fair future path, but not for a function that sits
    /// between ⌘C and the disk on a machine that may have no network at all.
    ///
    /// The order is: the things that name themselves, then the things that have to be
    /// argued for. A shebang names its interpreter outright, a JSON document either parses
    /// or does not, and a SQL statement has a shape no other language shares. Everything
    /// else is scored and has to clear ``bar`` — see the note there for why the bar is
    /// where it is.
    ///
    /// - Parameter text: Exactly what was copied, untrimmed.
    /// - Returns: The language, or `nil` when the evidence does not settle it. `nil` is not
    ///   a failure — it is the answer for every clip that is prose, and for every snippet
    ///   short or generic enough that two languages have an equal claim to it.
    public static func detect(_ text: String) -> CodeLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Two characters cannot carry two independent signals, so nothing below can ever
        // reach the bar on them. Returning early is honesty, not just speed.
        guard trimmed.count > 2 else { return nil }

        if trimmed.contains("```") { return nil }
        if isJSONDocument(trimmed) { return .json }

        let sample = String(trimmed.prefix(windowLength))
        if let named = shebangLanguage(in: sample) { return named }
        if isSQLStatement(sample) { return .sql }
        return highestScoring(in: sample)
    }

    // MARK: - The bar

    /// Points a language needs before it gets a chip.
    ///
    /// Signals are worth 2 when they are near-unique to one language and 1 when they are
    /// merely consistent with it, so three points is either one near-unique marker with
    /// something corroborating it, or three independent corroborating ones. What three
    /// rules out is the single token, and the single token is the whole problem: `->` is
    /// Rust, Python, PHP and C++; `let` is Swift, JavaScript and Rust; `end` is Ruby and
    /// Lua; `func` is Swift and Go. Any of them alone is a coincidence waiting to be
    /// printed on a chip.
    private static let bar = 3

    /// How far ahead of the runner-up the winner has to be.
    ///
    /// This is the part that protects Swift from TypeScript, which is the confusion that
    /// actually happens: both have `let`, `import`, a function keyword and `:` type
    /// annotations, so a one-point lead between them is one shared token falling one way
    /// rather than the other. That is not a reason to print anything. Two points is the
    /// weight of a near-unique signal, so a winner that clears the margin matched something
    /// the runner-up has no claim to at all.
    private static let margin = 2

    /// How much of the clip is read.
    ///
    /// About eighty lines of ordinary code, which is more than enough to tell a language —
    /// the first few lines usually settle it. The cap exists for the minified bundle and
    /// the megabyte of exported JSON: running ninety regular expressions over half a
    /// million characters on the copy path would be a stall the user feels in ⌘C, and
    /// reading further would not change the answer, because a minified file repeats itself.
    private static let windowLength = 4_000

    // MARK: - The ones that name themselves

    /// A shebang is not evidence, it is a declaration: the author wrote down which
    /// interpreter runs this file. Nothing scored below can outrank that, so it is checked
    /// first and returned immediately.
    ///
    /// An interpreter that is not one of ours — `perl`, `awk`, `tclsh` — deliberately falls
    /// through to scoring rather than being forced into ``shell``. It is a script, but not
    /// one we have a chip for, and inventing one would be exactly the wrong answer.
    private static func shebangLanguage(in text: String) -> CodeLanguage? {
        guard text.hasPrefix("#!") else { return nil }
        let line = text.prefix(while: { !$0.isNewline }).lowercased()
        if line.contains("python") { return .python }
        if line.contains("ruby") { return .ruby }
        if line.contains("node") || line.contains("deno") || line.contains("bun") {
            return .javascript
        }
        if line.contains("swift") { return .swift }
        if shells.contains(where: line.contains) { return .shell }
        return nil
    }

    private static let shells = ["bash", "zsh", "/sh", " sh", "dash", "ksh", "fish", "ash"]

    /// JSON is the one language in the list with a decidable answer, so it is decided
    /// rather than guessed: a real parser either accepts the whole document or it does not.
    ///
    /// That parse is also the entire JSON-versus-JavaScript-object-literal question.
    /// `{"retries": 3}` parses; `{ retries: 3 }` does not, because JSON has no unquoted
    /// keys — so the second one falls through to scoring and is judged as code, which is
    /// what it is. When a clip is valid JSON *and* a valid JavaScript literal, it is called
    /// JSON: a quoted-key object copied on its own came out of an API response or a config
    /// file far more often than out of a source file, and in a source file it would have
    /// had `const x =` in front of it, which is enough to stop it parsing.
    ///
    /// The top-level value has to be an object or an array. Bare `{}` and `[]` are excluded
    /// by the length check in ``detect(_:)`` for the same reason as every other two-token
    /// clip: there is nothing there to be sure about.
    private static func isJSONDocument(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    /// A SQL statement, as opposed to an English sentence that happens to use the words
    /// `select` and `from`.
    ///
    /// SQL gets its own gate because its keywords are ordinary English and its punctuation
    /// is almost nil, so the scoring below can neither find it reliably nor be trusted when
    /// it does. "Select an item from the list below" satisfies every clause-shape test you
    /// can write. Two guards separate the two, and both are properties of the language
    /// rather than heuristics:
    ///
    /// - A statement does not end in a full stop. SQL ends in a semicolon or in nothing;
    ///   `?` and `!` end questions and exclamations, not queries.
    /// - SQL has no articles. There is no `the` in a query, no `a`, no `your`. The veto is
    ///   waived when the statement corroborates itself some other way — a trailing
    ///   semicolon, a `SELECT *`, a second clause keyword — because a string literal in a
    ///   `WHERE` can legitimately contain English.
    ///
    /// Case is ignored throughout, because half the world writes `SELECT` and the other
    /// half writes `select`, and a third group alternates within one query.
    private static func isSQLStatement(_ text: String) -> Bool {
        guard let last = text.last, !".!?".contains(last) else { return false }
        guard text.contains(sqlClause) else { return false }
        return text.contains(sqlCorroboration) || !text.contains(englishArticle)
    }

    /// A verb and its object: the shape every SQL statement opens with. The object has to
    /// look like an identifier, which is what stops `from the` matching on the `the`.
    nonisolated(unsafe) private static let sqlClause =
        #/(?i)\bselect\b[^\n]{0,400}?\bfrom\s+[\w."`\[\]]+|\b(?:insert\s+into|update|delete\s+from|create\s+(?:table|index|view)|alter\s+table|drop\s+table|truncate\s+table)\s+[\w."`\[\]]+/#

    /// A second thing that only a query does, which is what buys the statement its way past
    /// the article veto.
    nonisolated(unsafe) private static let sqlCorroboration =
        #/(?i)\bselect\s+\*|;\s*$|\bas\s+\w+\b|\b(?:where|join|group\s+by|order\s+by|limit|having|values|distinct|primary\s+key|foreign\s+key|not\s+null)\b/#
        .anchorsMatchLineEndings()

    /// Determiners and modals. English is full of them and SQL contains none, which makes
    /// their presence the cheapest available proof that a sentence is a sentence.
    nonisolated(unsafe) private static let englishArticle =
        #/(?i)\b(?:the|a|an|this|these|those|my|your|our|their|please|should|would|could)\b/#

    // MARK: - Scoring

    /// The winner, if it both clears the bar and is clear of everyone else.
    ///
    /// Two languages tied at the top always produce `nil`, which is the point: a tie means
    /// the evidence names a family, not a language.
    private static func highestScoring(in sample: String) -> CodeLanguage? {
        var best: (language: CodeLanguage, score: Int)?
        var runnerUp = 0
        for language in allCases {
            let points = score(language, in: sample)
            if points > (best?.score ?? 0) {
                runnerUp = best?.score ?? 0
                best = (language, points)
            } else if points > runnerUp {
                runnerUp = points
            }
        }
        guard let best, best.score >= bar, best.score - runnerUp >= margin else { return nil }
        return best.language
    }

    /// Distinct signals, not occurrences.
    ///
    /// A file that says `console.log` forty times has said one thing forty times, and
    /// counting the repetitions would let a single habit outvote every other kind of
    /// evidence in the clip. Breadth is what distinguishes a language; volume is just
    /// length.
    private static func score(_ language: CodeLanguage, in sample: String) -> Int {
        let table = Signals.table(for: language)
        let strong = table.strong.count { sample.contains($0) }
        let supporting = table.supporting.count { sample.contains($0) }
        return strong * 2 + supporting
    }
}

/// What each language looks like, in two weights.
///
/// `strong` is for markers that one language has and the others essentially do not:
/// `\(…)` interpolation, `module.exports`, `elsif`, `:=`. `supporting` is for the things
/// that are consistent with a language without being owned by it — `nil`, `->`, a trailing
/// semicolon. Every pattern is written in a code-shaped form rather than as a bare word,
/// for the same reason ``CodeShapes`` does it: the word `class` appears in a paragraph
/// about timetables, and `class Foo {` does not.
private enum Signals {
    typealias Table = (strong: [Regex<Substring>], supporting: [Regex<Substring>])

    static func table(for language: CodeLanguage) -> Table {
        switch language {
        case .swift: (swiftStrong, swiftSupporting)
        case .python: (pythonStrong, pythonSupporting)
        case .ruby: (rubyStrong, rubySupporting)
        case .javascript: (javascriptStrong, javascriptSupporting)
        case .typescript: (typescriptStrong, typescriptSupporting)
        case .json: ([], [])
        case .sql: (sqlStrong, sqlSupporting)
        case .shell: (shellStrong, shellSupporting)
        case .html: (htmlStrong, htmlSupporting)
        case .css: (cssStrong, cssSupporting)
        case .go: (goStrong, goSupporting)
        case .rust: (rustStrong, rustSupporting)
        case .java: (javaStrong, javaSupporting)
        }
    }

    // MARK: - Swift

    nonisolated(unsafe) static let swiftStrong: [Regex<Substring>] = [
        // "\(name)" — string interpolation in this spelling belongs to Swift alone.
        #/\\\([^)\n]*\)/#,
        // guard … else { — no other language in the list has the statement at all.
        #/\bguard\b[^\n]*\belse\s*\{/#,
        // A function signature with an arrow return, which Go writes without one.
        #/\bfunc\s+\w+\s*(?:<[^>\n]*>)?\([^\n]*\)\s*(?:async\s+)?(?:throws\s+)?->\s*\S/#,
        // Attributes. Every one of these is Swift's spelling of an idea other languages
        // spell differently or not at all.
        #/@(?:MainActor|Sendable|escaping|objc|Published|State|discardableResult|available|Test|Suite)\b/#,
        // Keywords with no counterpart elsewhere.
        #/\b(?:mutating|nonisolated|associatedtype|willSet|didSet|deinit|fileprivate|unowned|typealias|@unchecked)\b/#,
        // A type declaration opening a line. Rust's `pub struct` and Go's `type … struct`
        // both fail this because of the words in front of the keyword.
        #/^[ \t]*(?:public\s+|internal\s+|private\s+)?(?:final\s+)?(?:struct|enum|protocol|extension|actor)\s+\w+/#
            .anchorsMatchLineEndings(),
    ]

    nonisolated(unsafe) static let swiftSupporting: [Regex<Substring>] = [
        #/\blet\s+\w+\s*(?::\s*[\w<>?\[\].]+\s*)?=/#,
        #/\bvar\s+\w+\s*:\s*[A-Z]\w*/#,
        // import of a capitalised module with nothing after it — Foundation, not "foo/bar".
        #/^[ \t]*import\s+[A-Z]\w*[ \t]*$/#.anchorsMatchLineEndings(),
        #/\bnil\b/#,
        #/\?\?|\bif\s+let\b|\btry\b|\bawait\s+\w/#,
        // A trailing closure with Swift's anonymous argument or its `in` binding.
        #/\{\s*(?:\$0|[\w,\s]+\bin\b)/#,
    ]

    // MARK: - Python

    nonisolated(unsafe) static let pythonStrong: [Regex<Substring>] = [
        // def with a colon. Ruby's def has none, and that one character is the whole
        // Python-versus-Ruby question.
        #/^[ \t]*(?:async\s+)?def\s+\w+\s*\([^\n]*\)\s*(?:->[^\n:]+)?:[ \t]*$/#
            .anchorsMatchLineEndings(),
        // A block header that ends in a colon rather than a brace.
        #/^[ \t]*(?:if|elif|else|for|while|try|except|finally|with|class)\b[^\n]*:[ \t]*$/#
            .anchorsMatchLineEndings(),
        // `from x import y`, or an import of a lower-case module — Swift's are capitalised.
        #/^[ \t]*(?:from\s+[\w.]+\s+import\s+\S|import\s+[a-z_][\w.]*[ \t]*$)/#
            .anchorsMatchLineEndings(),
        #/\belif\b/#,
        #/\b__(?:init|main|name|repr|str|dict)__\b/#,
        // An f-string with something substituted into it.
        #/\bf["'][^"'\n]*\{/#,
    ]

    nonisolated(unsafe) static let pythonSupporting: [Regex<Substring>] = [
        #/\bself\.\w+/#,
        #/\b(?:None|True|False)\b/#,
        #/\b(?:lambda|yield|pass|raise|assert|del|nonlocal)\b/#,
        #/\b(?:len|range|enumerate|isinstance|dict|list|str|int)\s*\(/#,
    ]

    // MARK: - Ruby

    nonisolated(unsafe) static let rubyStrong: [Regex<Substring>] = [
        // `end` alone on a line. Nothing else here closes a block with a word.
        #/^[ \t]*end[ \t]*$/#.anchorsMatchLineEndings(),
        // def without a colon, and with Ruby's question-mark and bang method names.
        #/^[ \t]*def\s+[\w.]+[?!]?(?:\s*\([^)\n]*\))?[ \t]*$/#.anchorsMatchLineEndings(),
        #/\belsif\b/#,
        #/\bputs\s|\bdo\s*\|[^|\n]*\|/#,
        // An instance variable being read or written.
        #/@\w+\s*(?:=[^=]|\.)/#,
        #/^[ \t]*require(?:_relative)?\s+["']/#.anchorsMatchLineEndings(),
    ]

    nonisolated(unsafe) static let rubySupporting: [Regex<Substring>] = [
        #/\bnil\b/#,
        #/\b(?:unless|attr_accessor|attr_reader|yield|freeze)\b/#,
        #/\.each\b|\.map\s*(?:\{|do\b)/#,
        // The hash rocket, in the only form that cannot be a JavaScript arrow.
        #/:\w+\s*=>/#,
        #/\bclass\s+[A-Z]\w*\s*<\s*[A-Z]|\bmodule\s+[A-Z]\w*/#,
    ]

    // MARK: - JavaScript and TypeScript

    /// Shared by both, because both are true of both. Keeping these out of either
    /// language's strong list is what makes the margin rule work between them: neither can
    /// win on syntax they have in common.
    nonisolated(unsafe) static let ecmaScript: [Regex<Substring>] = [
        #/\bconst\s+\w+\s*=/#,
        #/\bfunction\s+\w+\s*\(|=>\s*[({\w]/#,
        #/\basync\s+function\b|\bawait\s+\w|\.then\s*\(|new\s+Promise\b/#,
        #/\b(?:null|undefined|typeof|instanceof)\b/#,
        #/===|!==|\?\.|\?\?|\.\.\./#,
        #/\bexport\s+(?:default|const|function|class|\{)/#,
        #/\bimport\s+[^\n]*\bfrom\s+["']/#,
        // Runtime, not language: valid in both, so it belongs to neither.
        #/\bconsole\.(?:log|error|warn|info)\s*\(|\b(?:document|window)\.\w+|\bprocess\.env\b/#,
    ]

    nonisolated(unsafe) static let javascriptStrong: [Regex<Substring>] = [
        #/\brequire\s*\(\s*["']/#,
        #/\bmodule\.exports\b|\bexports\.\w+\s*=/#,
    ]

    nonisolated(unsafe) static let javascriptSupporting: [Regex<Substring>] =
        ecmaScript + [
            #/\bvar\s+\w+\s*=/#,
            #/["']use strict["']|\.prototype\.\w+/#,
        ]

    /// TypeScript's identity is its types and nothing else. That is also why untyped modern
    /// ECMAScript ends up `nil` rather than `typescript`: with the annotations stripped out
    /// there is nothing left that is TypeScript and not JavaScript, and of the two labels
    /// `javascript` is the one that stays true either way.
    nonisolated(unsafe) static let typescriptStrong: [Regex<Substring>] = [
        #/:\s*(?:string|number|boolean|void|any|unknown|never|object|bigint|symbol)\b/#,
        #/\btype\s+\w+(?:<[^>\n]*>)?\s*=/#,
        #/\binterface\s+\w+(?:\s+extends\s+[\w,\s]+)?\s*\{/#,
        #/:\s*(?:Promise|Array|Record|Map|Set|Partial|Readonly|ReadonlyArray)\s*</#,
        #/\bas\s+(?:const|unknown)\b|\breadonly\s+\w+\s*:|\bimplements\s+\w+|\bdeclare\s+(?:module|const|function)\b/#,
        // A parameter list closing straight into a return-type annotation.
        #/\)\s*:\s*[\w<>\[\]|\s]+\s*(?:=>|\{)/#,
    ]

    nonisolated(unsafe) static let typescriptSupporting: [Regex<Substring>] = ecmaScript

    // MARK: - SQL

    /// Scoring for SQL fragments — a `WHERE` clause on its own, a column list — that never
    /// reach ``CodeLanguage/isSQLStatement(_:)`` because they are not whole statements.
    nonisolated(unsafe) static let sqlStrong: [Regex<Substring>] = [
        #/(?i)\bselect\b[^\n]*\bfrom\b/#,
        #/(?i)\b(?:insert\s+into|update\s+\w+\s+set|delete\s+from|create\s+(?:table|index|view)|alter\s+table|drop\s+table)\b/#,
        #/(?i)\b(?:inner\s+join|left\s+join|right\s+join|group\s+by|order\s+by|having|union\s+all)\b/#,
    ]

    nonisolated(unsafe) static let sqlSupporting: [Regex<Substring>] = [
        #/(?i)\bwhere\b[^\n]*[=<>]/#,
        #/(?i)\b(?:varchar|integer|timestamp|boolean\s+default|primary\s+key|foreign\s+key|not\s+null)\b/#,
        #/(?i)\b(?:count|sum|avg|coalesce)\s*\(/#,
        #/(?i)\blimit\s+\d|\bdistinct\b|\bvalues\s*\(/#,
    ]

    // MARK: - Shell

    nonisolated(unsafe) static let shellStrong: [Regex<Substring>] = [
        // The word-shaped block terminators.
        #/^[ \t]*(?:fi|done|esac)[ \t]*$/#.anchorsMatchLineEndings(),
        // Variable expansion. Written so that a JavaScript template's `${obj.prop}` — which
        // has a dot in it — does not match.
        #/\$(?:\{[\w:%\/*@#-]+\}|[A-Za-z_]\w*|\(|[@?#!*])/#,
        #/^[ \t]*(?:export|local|readonly|declare)\s+\w+=/#.anchorsMatchLineEndings(),
        // A test, in either the bracket form or the operator form.
        #/\[\[\s|\s-(?:eq|ne|gt|lt|ge|le|z|n|f|d|e)\s/#,
        // A loop or conditional in shell's punctuation, or a function definition.
        #/;\s*(?:then|do)\b|^[ \t]*\w+\(\)\s*\{/#.anchorsMatchLineEndings(),
        #/\bset\s+-[a-z]+\b|\|\s*(?:grep|awk|sed|xargs|head|tail|sort|uniq|wc|jq)\b/#,
    ]

    nonisolated(unsafe) static let shellSupporting: [Regex<Substring>] = [
        #/^[ \t]*(?:echo|cd|mkdir|rm|cp|mv|chmod|source|sudo|exit|trap|shift)\s/#
            .anchorsMatchLineEndings(),
        #/2>&1|>>\s*\S|\/dev\/null/#,
        #/`[^`\n]+`/#,
        #/\s--[a-z][\w-]*\b/#,
    ]

    // MARK: - HTML

    /// Deliberately weighted towards document-level elements rather than any tag at all, so
    /// that JSX inside a TypeScript component does not outscore the TypeScript around it.
    nonisolated(unsafe) static let htmlStrong: [Regex<Substring>] = [
        #/(?i)<!DOCTYPE\s+html|<html\b/#,
        #/(?i)<(?:head|body|meta|link|title|script|style)\b/#,
        #/(?i)<\/(?:div|span|p|a|ul|ol|li|h[1-6]|table|tr|td|form|button|section|header|footer|nav|main|article)>/#,
    ]

    nonisolated(unsafe) static let htmlSupporting: [Regex<Substring>] = [
        #/(?i)<(?:div|span|p|a|ul|ol|li|h[1-6]|table|tr|td|form|button|section|header|footer|nav|main|article)(?:\s[^<>\n]*)?>/#,
        #/(?i)\s(?:class|id|href|src|alt|rel|charset)\s*=\s*["']/#,
        #/&(?:nbsp|amp|lt|gt|quot);|<!--/#,
    ]

    // MARK: - CSS

    nonisolated(unsafe) static let cssStrong: [Regex<Substring>] = [
        // A selector alone on a line, opening a block. Descendant combinators are left out
        // on purpose: allowing spaces between the parts would make `export interface Clip {`
        // a selector.
        #/^[ \t]*[.#]?[\w-]+(?:[.#:][\w()-]+)*(?:\s*[,>+~]\s*[^\n{]+)?\s*\{[ \t]*$/#
            .anchorsMatchLineEndings(),
        #/@(?:media|import|keyframes|font-face|supports|tailwind|apply|layer)\b/#,
        #/::?(?:hover|focus|active|before|after|first-child|last-child|nth-child|root)\b/#,
        #/\b(?:margin|padding|display|position|background(?:-color)?|font-size|border-radius|box-shadow|flex-direction|grid-template)\s*:/#,
    ]

    nonisolated(unsafe) static let cssSupporting: [Regex<Substring>] = [
        // A property and its value, terminated. Shares its shape with a TypeScript member,
        // which is why it is only worth a point.
        #/^[ \t]*[a-z-]+\s*:\s*[^;{}\n]+;[ \t]*$/#.anchorsMatchLineEndings(),
        #/\d+(?:px|rem|em|vh|vw)\b/#,
        #/var\(--[\w-]+\)|--[\w-]+\s*:/#,
        #/!important\b/#,
    ]

    // MARK: - Go

    nonisolated(unsafe) static let goStrong: [Regex<Substring>] = [
        #/^[ \t]*package\s+\w+[ \t]*$/#.anchorsMatchLineEndings(),
        #/:=/#,
        // A function or method whose return type sits between the brackets and the brace,
        // with no arrow anywhere — which is how Go differs from Swift and Rust.
        #/\bfunc\s+(?:\([^)\n]*\)\s*)?\w+\s*\([^)\n]*\)\s*(?:\([^)\n]*\)|[\w*.\[\]]+)?\s*\{/#,
        #/\bif\s+err\s*!=\s*nil\b/#,
        #/\btype\s+\w+\s+(?:struct|interface)\s*\{/#,
        #/\b(?:defer|chan)\b|\bgo\s+\w+\(|\bfmt\.[A-Z]\w*\(/#,
    ]

    nonisolated(unsafe) static let goSupporting: [Regex<Substring>] = [
        #/\bnil\b/#,
        #/\bimport\s*\(/#,
        #/\brange\s+\w/#,
        #/\b(?:int64|float64|interface\{\}|error\b)/#,
    ]

    // MARK: - Rust

    nonisolated(unsafe) static let rustStrong: [Regex<Substring>] = [
        #/\bfn\s+\w+\s*(?:<[^>\n]*>)?\(/#,
        #/\blet\s+mut\b|\bpub\s+(?:fn|struct|enum|mod|use|trait|const)\b/#,
        #/\bimpl\b|\btrait\s+\w+/#,
        #/&(?:str\b|mut\s|self\b)|\b(?:Vec|Option|Result|Box|Arc|HashMap)</#,
        #/\b(?:Some|Ok|Err)\(|\.unwrap\(\)|\.expect\s*\(/#,
        // A macro invocation: println!(…), vec![…].
        #/\b\w+!\s*[(\[]/#,
    ]

    nonisolated(unsafe) static let rustSupporting: [Regex<Substring>] = [
        #/->\s*\w/#,
        #/\buse\s+[\w:]+::|::\w/#,
        #/\bmatch\s+[\w.()]+\s*\{/#,
        #/\b(?:i32|u32|u8|usize|f64|dyn|crate)\b/#,
    ]

    // MARK: - Java

    nonisolated(unsafe) static let javaStrong: [Regex<Substring>] = [
        #/\bpublic\s+(?:static\s+)?(?:final\s+)?(?:void|class|int|String|boolean|double|long)\b/#,
        #/\bSystem\.(?:out|err)\.print/#,
        #/^[ \t]*import\s+[\w.]+\s*;/#.anchorsMatchLineEndings(),
        #/@(?:Override|Autowired|Component|Service|Entity|SuppressWarnings|SpringBootApplication)\b/#,
        #/\b(?:ArrayList|HashMap|StringBuilder)\b|\b(?:List|Map|Optional)<[A-Z]/#,
        #/^[ \t]*package\s+[\w.]+\s*;/#.anchorsMatchLineEndings(),
    ]

    nonisolated(unsafe) static let javaSupporting: [Regex<Substring>] = [
        #/\bnew\s+[A-Z]\w*\s*\(/#,
        #/\b(?:extends|implements)\s+[A-Z]\w*/#,
        #/\bthrows\s+\w*Exception\b|\bcatch\s*\(\s*\w*Exception/#,
        #/\b(?:private|protected)\s+[\w<>\[\]]+\s+\w+\s*[;=(]/#,
    ]
}
