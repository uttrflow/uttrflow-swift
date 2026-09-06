// Tests for re-indenting a clip.

import Testing

@testable import UttrflowClipboard

@Suite("Making a clip's indentation consistent")
struct CodeReindentTests {
    // MARK: - The guarantee

    /// The whole safety argument in one assertion over every fixture: only leading whitespace changes.
    @Test("changes nothing but leading whitespace", arguments: everyFixture)
    func onlyLeadingWhitespaceChanges(_ input: String) {
        let output = CodeReindent.reindented(input) ?? input
        #expect(bodies(of: output) == bodies(of: input))
    }

    /// Line count survives, stated apart from the body comparison so each promise fails on its own.
    @Test("keeps the number of lines", arguments: everyFixture)
    func lineCountSurvives(_ input: String) {
        let output = CodeReindent.reindented(input) ?? input
        #expect(output.components(separatedBy: "\n").count == input.components(separatedBy: "\n").count)
    }

    /// Whether a clip ends in a newline decides whether pasting it starts a new line.
    @Test("keeps the final newline, or its absence", arguments: everyFixture)
    func finalNewlineSurvives(_ input: String) {
        let output = CodeReindent.reindented(input) ?? input
        #expect(output.hasSuffix("\n") == input.hasSuffix("\n"))
    }

    private func bodies(of text: String) -> [String] {
        text.components(separatedBy: "\n").map { line in
            String(line.drop(while: { $0 == " " || $0 == "\t" }))
        }
    }

    // MARK: - The work it does do

    /// The case the feature exists for: one snippet assembled out of two editors.
    @Test("settles a clip that mixes tabs and spaces")
    func mixedIndentation() {
        let input = "function greet(name) {\n  if (name) {\n\treturn \"hi \" + name;\n  }\n}"
        #expect(
            CodeReindent.reindented(input)
                == "function greet(name) {\n  if (name) {\n  return \"hi \" + name;\n  }\n}")
    }

    /// Two-space code stays two-space: the unit is measured from the clip, never chosen for it.
    @Test("keeps the clip's own indent width")
    func unitIsMeasuredNotImposed() {
        let input = "a\n  b\n    c\n\td\n"
        #expect(CodeReindent.reindented(input) == "a\n  b\n    c\n  d\n")
    }

    /// The same clip with a wider unit, to show the width really does come from the text.
    @Test("measures a four-space unit as four")
    func fourSpaceUnit() {
        let input = "a\n    b\n        c\n\td\n"
        #expect(CodeReindent.reindented(input) == "a\n    b\n        c\n    d\n")
    }

    /// Tabs have to win outright: five tab-indented lines against one space-indented one.
    @Test("converts to tabs when tabs are the clip's style")
    func tabsWinWhenTheyDominate() {
        let input = "class A {\n\tvoid f() {\n\t\tg();\n\t}\n    void h() {\n\t\ti();\n\t}\n}"
        #expect(
            CodeReindent.reindented(input)
                == "class A {\n\tvoid f() {\n\t\tg();\n\t}\n\tvoid h() {\n\t\ti();\n\t}\n}")
    }

    /// One tab against one space run; the tie goes to spaces, the smaller change.
    @Test("breaks a tie towards spaces")
    func tieGoesToSpaces() {
        #expect(CodeReindent.reindented("a\n  b\n\tc") == "a\n  b\n  c")
    }

    /// A clip cut from the middle of a file starts already indented.
    @Test("accepts a snippet that starts indented")
    func snippetStartingIndented() {
        #expect(CodeReindent.reindented("        a\n    b\n\tc") == "        a\n    b\n    c")
    }

    // MARK: - What survives untouched

    /// Trailing whitespace is left exactly as found; stripping it would be a second edit.
    @Test("never touches trailing whitespace")
    func trailingWhitespaceIsLeftAlone() {
        #expect(CodeReindent.reindented("a\n  b   \n\tc\t\n") == "a\n  b   \n  c\t\n")
    }

    /// A whitespace-only line has no body to indent and is passed through untouched.
    @Test("leaves whitespace-only lines exactly as they are")
    func blankLinesAreLeftAlone() {
        #expect(CodeReindent.reindented("a\n\t\n  b\n\tc") == "a\n\t\n  b\n  c")
    }

    /// Carriage returns are ordinary trailing content, so a Windows clip keeps its line endings.
    @Test("keeps CRLF line endings")
    func carriageReturnsSurvive() {
        #expect(CodeReindent.reindented("a\r\n  b\r\n\tc\r\n") == "a\r\n  b\r\n  c\r\n")
    }

    // MARK: - Nothing to do

    @Test(
        "offers nothing when there is nothing to fix",
        arguments: [
            "",
            "   ",
            "let x = 1",
            "        indented one-liner",
            "\n",
            "  \n\t\n",
            "a\nb\nc\n",
            "a\n  b\n    c\n",
            "a\n\tb\n\t\tc\n",
        ])
    func alreadyFine(_ text: String) {
        #expect(CodeReindent.reindented(text) == nil)
    }

    // MARK: - What it refuses

    /// Inside a multi-line literal the leading whitespace is what the program prints.
    @Test(
        "refuses a clip holding a multi-line string literal",
        arguments: [
            // Swift.
            "func f() {\n\tlet usage = \"\"\"\n        uttrflow run\n\t\"\"\"\n}",
            // Python.
            "def f():\n\tprint('''\n        indented output\n    ''')\n  return",
            // A JavaScript template literal, and every other backtick with it.
            "function f() {\n\tconst q = `\n        SELECT 1\n    `;\n  return q;\n}",
            // Markdown fencing a block, which is the same problem wearing a hat.
            "Steps:\n\n```\n  install\n\tbuild\n```\n",
            // Shell heredocs, in the three spellings that occur.
            "run() {\n\tcat <<EOF\n  verbatim\nEOF\n}\n  done",
            "run() {\n\tcat <<-'EOF' > out\n  verbatim\nEOF\n}\n  done",
            "def q\n\tsql = <<~SQL\n        select 1\n    SQL\n  end",
        ])
    func literalWhitespace(_ text: String) {
        #expect(CodeReindent.reindented(text) == nil)
    }

    /// A double-quoted string left open carries on onto the next line, whatever the language.
    @Test("refuses a clip with an unbalanced quote")
    func unbalancedQuote() {
        #expect(CodeReindent.reindented("var s = @\"first\n  second\";\n\tthird") == nil)
    }

    /// Escapes are discounted, or every clip containing `\"` would be refused.
    @Test("still works when a quote is escaped")
    func escapedQuotesDoNotCount() {
        #expect(
            CodeReindent.reindented("f() {\n  print(\"a \\\" b\");\n\tg();\n}")
                == "f() {\n  print(\"a \\\" b\");\n  g();\n}")
        // A trailing backslash escapes nothing, and must not swallow a later quote.
        #expect(CodeReindent.reindented("a\n  b \\\n\tc") == "a\n  b \\\n  c")
    }

    /// A recipe line is a recipe line because it starts with a tab, so makefiles are refused outright.
    @Test("refuses a makefile")
    func makefiles() {
        #expect(CodeReindent.reindented("build:\n\tswift build\n  echo done") == nil)
        #expect(CodeReindent.reindented(".PHONY: build\nbuild:\n\tswift build\n  x") == nil)
    }

    /// The same shape catches tab-bodied Python, where a wrong level moves a statement.
    @Test("refuses tab-and-space Python")
    func indentationSensitiveLanguages() {
        #expect(CodeReindent.reindented("def f():\n\tif x:\n\t\treturn 1\n    return 2") == nil)
    }

    /// Tabs followed by spaces on one line need a tab width to be read at all.
    @Test("refuses an indent that mixes tabs and spaces on one line")
    func mixedWithinOneLine() {
        #expect(CodeReindent.reindented("a\n  b\n\t  c") == nil)
        #expect(CodeReindent.reindented("a\n  b\n  \tc") == nil)
    }

    @Test(
        "refuses a width it cannot read as a unit",
        arguments: [
            // A single space is nobody's indent level, and would divide every other width.
            "a\n b\n\tc",
            // Wider than anyone sets a tab stop.
            "a\n          b\n\tc",
            // Four and six agree on nothing.
            "a\n    b\n      c\n\td",
        ])
    func unreadableUnit(_ text: String) {
        #expect(CodeReindent.reindented(text) == nil)
    }

    /// Code enters one block at a time; a jump of three levels says the unit is wrong.
    @Test("refuses indentation that climbs too fast to be indentation")
    func implausibleClimb() {
        #expect(CodeReindent.reindented("a\n  b\n\tc\n        d") == nil)
    }
}

/// Every clip in the suite, so the safety property is asserted over the refused ones too.
private let everyFixture: [String] = [
    "",
    "   ",
    "\n",
    "  \n\t\n",
    "let x = 1",
    "        indented one-liner",
    "a\nb\nc\n",
    "a\n  b\n    c\n",
    "a\n\tb\n\t\tc\n",
    "a\n  b\n\tc",
    "a\n  b\n    c\n\td\n",
    "a\n    b\n        c\n\td\n",
    "a\n  b   \n\tc\t\n",
    "a\n\t\n  b\n\tc",
    "a\r\n  b\r\n\tc\r\n",
    "        a\n    b\n\tc",
    "class A {\n\tvoid f() {\n\t\tg();\n\t}\n    void h() {\n\t\ti();\n\t}\n}",
    "function greet(name) {\n  if (name) {\n\treturn \"hi \" + name;\n  }\n}",
    "f() {\n  print(\"a \\\" b\");\n\tg();\n}",
    "a\n  b \\\n\tc",
    "var s = @\"first\n  second\";\n\tthird",
    "func f() {\n\tlet usage = \"\"\"\n        uttrflow run\n\t\"\"\"\n}",
    "def f():\n\tprint('''\n        indented output\n    ''')\n  return",
    "function f() {\n\tconst q = `\n        SELECT 1\n    `;\n  return q;\n}",
    "Steps:\n\n```\n  install\n\tbuild\n```\n",
    "run() {\n\tcat <<EOF\n  verbatim\nEOF\n}\n  done",
    "run() {\n\tcat <<-'EOF' > out\n  verbatim\nEOF\n}\n  done",
    "def q\n\tsql = <<~SQL\n        select 1\n    SQL\n  end",
    "build:\n\tswift build\n  echo done",
    ".PHONY: build\nbuild:\n\tswift build\n  x",
    "def f():\n\tif x:\n\t\treturn 1\n    return 2",
    "a\n  b\n\t  c",
    "a\n  b\n  \tc",
    "a\n b\n\tc",
    "a\n          b\n\tc",
    "a\n    b\n      c\n\td",
    "a\n  b\n\tc\n        d",
]
