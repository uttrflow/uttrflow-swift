// Which language a code clip is written in.

import Foundation

/// Which language a code clip is written in, when the clip alone says so; `nil` is the usual answer.
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

    /// The short form for a row chip; only the three habitually abbreviated names get one.
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
    /// The language of `text`, or `nil` when unsettled. See Docs/clipboard-code-language.md.
    public static func detect(_ text: String) -> CodeLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Two characters cannot carry two independent signals, so nothing below can reach the bar.
        guard trimmed.count > 2 else { return nil }

        if trimmed.contains("```") { return nil }
        if isJSONDocument(trimmed) { return .json }

        let sample = String(trimmed.prefix(windowLength))
        if let named = shebangLanguage(in: sample) { return named }
        if isSQLStatement(sample) { return .sql }
        return highestScoring(in: sample)
    }

    // MARK: - The bar

    /// Points a language needs for a chip: one near-unique marker plus corroboration, never a single token.
    private static let bar = 3

    /// How far ahead of the runner-up the winner must be: the weight of one near-unique signal.
    private static let margin = 2

    /// How much of the clip is read: about eighty lines, so a minified bundle cannot stall ⌘C.
    private static let windowLength = 4_000

    // MARK: - The ones that name themselves

    /// A shebang names its interpreter outright; one without a chip of its own falls through to scoring.
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

    /// Parses rather than guesses; `{ retries: 3 }` fails on its unquoted key and falls through to scoring.
    private static func isJSONDocument(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil
    }

    /// A SQL statement rather than an English sentence: no full stop, and no articles unless corroborated.
    private static func isSQLStatement(_ text: String) -> Bool {
        guard let last = text.last, !".!?".contains(last) else { return false }
        guard text.contains(sqlClause) else { return false }
        return text.contains(sqlCorroboration) || !text.contains(englishArticle)
    }

    /// A verb and an identifier-shaped object, the shape every SQL statement opens with.
    nonisolated(unsafe) private static let sqlClause =
        #/(?i)\bselect\b[^\n]{0,400}?\bfrom\s+[\w."`\[\]]+|\b(?:insert\s+into|update|delete\s+from|create\s+(?:table|index|view)|alter\s+table|drop\s+table|truncate\s+table)\s+[\w."`\[\]]+/#

    /// A second thing only a query does, which buys the statement past the article veto.
    nonisolated(unsafe) private static let sqlCorroboration =
        #/(?i)\bselect\s+\*|;\s*$|\bas\s+\w+\b|\b(?:where|join|group\s+by|order\s+by|limit|having|values|distinct|primary\s+key|foreign\s+key|not\s+null)\b/#
        .anchorsMatchLineEndings()

    /// Determiners and modals, which English is full of and SQL contains none of.
    nonisolated(unsafe) private static let englishArticle =
        #/(?i)\b(?:the|a|an|this|these|those|my|your|our|their|please|should|would|could)\b/#

    // MARK: - Scoring

    /// The winner, if it clears the bar and the margin; a tie names a family, not a language.
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

    /// Distinct signals, not occurrences, so one habit repeated forty times cannot outvote the rest.
    private static func score(_ language: CodeLanguage, in sample: String) -> Int {
        let table = Signals.table(for: language)
        let strong = table.strong.count { sample.contains($0) }
        let supporting = table.supporting.count { sample.contains($0) }
        return strong * 2 + supporting
    }
}

/// What each language looks like, in two weights: markers it owns and markers merely consistent with it.
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
        // Attributes that are Swift's spelling alone.
        #/@(?:MainActor|Sendable|escaping|objc|Published|State|discardableResult|available|Test|Suite)\b/#,
        // Keywords with no counterpart elsewhere.
        #/\b(?:mutating|nonisolated|associatedtype|willSet|didSet|deinit|fileprivate|unowned|typealias|@unchecked)\b/#,
        // A type declaration opening a line; Rust's `pub struct` and Go's `type … struct` fail on the prefix.
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
        // def with a colon; Ruby's def has none.
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

    /// Shared by both, so neither JavaScript nor TypeScript can win on syntax they have in common.
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

    /// TypeScript's identity is its types; untyped modern ECMAScript ends up `javascript`, which stays true.
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

    /// Scoring for SQL fragments — a `WHERE` clause, a column list — that are not whole statements.
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
        // Variable expansion, written so a JavaScript template's `${obj.prop}` does not match.
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

    /// Weighted towards document-level elements, so JSX inside a TypeScript component does not win.
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
        // A selector alone on a line; no descendant combinators, or `export interface Clip {` matches.
        #/^[ \t]*[.#]?[\w-]+(?:[.#:][\w()-]+)*(?:\s*[,>+~]\s*[^\n{]+)?\s*\{[ \t]*$/#
            .anchorsMatchLineEndings(),
        #/@(?:media|import|keyframes|font-face|supports|tailwind|apply|layer)\b/#,
        #/::?(?:hover|focus|active|before|after|first-child|last-child|nth-child|root)\b/#,
        #/\b(?:margin|padding|display|position|background(?:-color)?|font-size|border-radius|box-shadow|flex-direction|grid-template)\s*:/#,
    ]

    nonisolated(unsafe) static let cssSupporting: [Regex<Substring>] = [
        // A property and its value, terminated; shares its shape with a TypeScript member, so one point.
        #/^[ \t]*[a-z-]+\s*:\s*[^;{}\n]+;[ \t]*$/#.anchorsMatchLineEndings(),
        #/\d+(?:px|rem|em|vh|vw)\b/#,
        #/var\(--[\w-]+\)|--[\w-]+\s*:/#,
        #/!important\b/#,
    ]

    // MARK: - Go

    nonisolated(unsafe) static let goStrong: [Regex<Substring>] = [
        #/^[ \t]*package\s+\w+[ \t]*$/#.anchorsMatchLineEndings(),
        #/:=/#,
        // A return type between the brackets and the brace with no arrow, unlike Swift and Rust.
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
