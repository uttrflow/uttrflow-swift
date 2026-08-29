import Testing

@testable import UttrflowClipboard

/// What a formatted clip becomes on its way into somewhere that cannot show formatting.
///
/// The fixtures are written the way the editors people keep notes in actually write
/// them — Apple Notes labels the list, GitHub puts a real `<input>` in the item, TipTap
/// uses a data attribute — because a degradation rule tested against invented markup is a
/// rule that has not been tested.
@Suite("What a plain target receives")
struct RichTextPlainFormTests {
    // MARK: - Headings

    /// Weight is gone and nothing is put in its place. A `#` would be as wrong as a `**`:
    /// the user did not type it, and in a commit message they would have to delete it.
    /// The blank line does the work instead, being whitespace rather than punctuation.
    @Test("keeps a heading's words and drops its weight")
    func heading() {
        let out = RichTextPlainForm.plainText(fromHTML: "<h1>Shopping</h1><p>Before Friday.</p>")
        #expect(out == "Shopping\n\nBefore Friday.")
    }

    @Test("marks a heading with nothing at all", arguments: 1...6)
    func headingLevels(_ level: Int) {
        let out = RichTextPlainForm.plainText(fromHTML: "<h\(level)>Notes</h\(level)>")
        #expect(out == "Notes")
    }

    @Test("separates headings from each other without stacking blank lines")
    func headingRun() {
        let out = RichTextPlainForm.plainText(fromHTML: "<h1>A</h1><h2>B</h2><p>c</p><h3>D</h3>")
        #expect(out == "A\n\nB\n\nc\n\nD")
    }

    // MARK: - Emphasis

    /// The rule the whole feature is named for, in its smallest form. Asterisks would be
    /// noise a person did not type, so bold arrives as words.
    @Test(
        "gives emphasis back as plain words",
        arguments: [
            "<p><strong>Ship</strong> the <em>fix</em> today.</p>",
            "<p><b>Ship</b> the <i>fix</i> today.</p>",
            "<p><span style=\"font-weight:700\"><b>Ship</b></span> the <u><i>fix</i></u> today.</p>",
        ])
    func emphasis(_ html: String) {
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "Ship the fix today.")
        #expect(!out.contains("*"))
    }

    /// Whitespace between two inline elements is the only thing keeping two words apart.
    @Test("keeps the space between adjacent inline runs")
    func spaceBetweenInlines() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p><b>one</b> <em>two</em></p>") == "one two")
        #expect(RichTextPlainForm.plainText(fromHTML: "<p><b>one</b><em>two</em></p>") == "onetwo")
    }

    // MARK: - Lists

    @Test("turns bullets into a bullet")
    func unorderedList() {
        let out = RichTextPlainForm.plainText(fromHTML: "<ul><li>Milk</li><li>Bread</li></ul>")
        #expect(out == "\u{2022} Milk\n\u{2022} Bread")
    }

    /// The tenth item is the one that catches a numbering scheme out.
    @Test("numbers an ordered list past nine")
    func orderedList() {
        let items = (1...12).map { "<li>step \($0)</li>" }.joined()
        let out = RichTextPlainForm.plainText(fromHTML: "<ol>\(items)</ol>")
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 12)
        #expect(lines.first == "1. step 1")
        #expect(lines.dropFirst(9).first == "10. step 10")
        #expect(lines.last == "12. step 12")
    }

    @Test("indents a nested list under its parent")
    func nestedList() {
        let html = """
            <ul><li>Fruit<ul><li>Apples</li><li>Pears</li></ul></li><li>Bread</li></ul>
            """
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "\u{2022} Fruit\n  \u{2022} Apples\n  \u{2022} Pears\n\u{2022} Bread")
    }

    @Test("keeps ordered numbering per level")
    func nestedOrderedList() {
        let html = "<ol><li>one<ol><li>inner</li><li>inner</li></ol></li><li>two</li></ol>"
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "1. one\n  1. inner\n  2. inner\n2. two")
    }

    /// A bullet with nothing after it is rubbish somebody has to delete.
    @Test("gives an empty item no line of its own")
    func emptyItem() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<ul><li></li><li>Milk</li></ul>") == "\u{2022} Milk")
        #expect(RichTextPlainForm.plainText(fromHTML: "<ul><li>Milk</li><li></li></ul>") == "\u{2022} Milk")
    }

    /// An `<li>` that never met a list still knows it is an item.
    @Test("survives a list item with no list around it")
    func strayItem() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<li>loose</li>") == "\u{2022} loose")
        #expect(RichTextPlainForm.plainText(fromHTML: "</ul><p>after</p>") == "after")
    }

    // MARK: - Checklists

    /// Apple Notes labels the list and the item; GitHub labels neither and puts a real
    /// `<input>` inside; TipTap and ProseMirror use data attributes. The clip comes from
    /// whichever one the user happened to be in, so all three are read.
    @Test(
        "turns a checklist into boxes",
        arguments: [
            """
            <ul class="checklist"><li class="checked">Passport</li>\
            <li class="unchecked">Adapter</li></ul>
            """,
            """
            <ul class="contains-task-list">\
            <li class="task-list-item"><input type="checkbox" checked> Passport</li>\
            <li class="task-list-item"><input type="checkbox"> Adapter</li></ul>
            """,
            """
            <ul data-type="taskList"><li data-checked="true"><p>Passport</p></li>\
            <li data-checked="false"><p>Adapter</p></li></ul>
            """,
        ])
    func checklists(_ html: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "[x] Passport\n[ ] Adapter")
    }

    /// `unchecked` contains `checked`, and a substring test would tick every box in an
    /// untouched list.
    @Test("does not read unchecked as checked")
    func uncheckedIsNotChecked() {
        let out = RichTextPlainForm.plainText(fromHTML: #"<ul><li class="unchecked">Pack</li></ul>"#)
        #expect(out == "[ ] Pack")
    }

    /// Apple Notes labels the list; an item inside it that says nothing about itself is
    /// still a box, and an empty one.
    @Test("takes an item's box from the list when the item is silent")
    func checklistWithoutItemClasses() {
        let html = #"<ul class="checklist"><li>Pack</li><li>Print tickets</li></ul>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "[ ] Pack\n[ ] Print tickets")
    }

    @Test("indents a nested checklist")
    func nestedChecklist() {
        let html = """
            <ul class="checklist"><li class="checked">Trip\
            <ul class="checklist"><li class="unchecked">Adapter</li></ul></li></ul>
            """
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "[x] Trip\n  [ ] Adapter")
    }

    @Test("writes a box for a checkbox that belongs to no list")
    func standaloneCheckbox() {
        let html = #"<p><input type="checkbox"> Water the plants</p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "[ ] Water the plants")
        let ticked = #"<p><input type="checkbox" checked="checked"> Water the plants</p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: ticked) == "[x] Water the plants")
    }

    @Test("leaves inputs that are not checkboxes out of it")
    func otherInputs() {
        let html = #"<p>Name <input type="text" value="ignored"> here</p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Name here")
    }

    @Test("reads an aria-checked checklist")
    func ariaChecklist() {
        let html = #"<ul><li role="checkbox" aria-checked="true">Filed</li></ul>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "[x] Filed")
    }

    // MARK: - Links

    /// The url is kept because a plain target cannot hide it behind a word: dropping it
    /// loses the only part of the link carrying information.
    @Test("keeps a link's destination beside its text")
    func linkWithText() {
        let html = #"<p>See <a href="https://example.com/docs">the docs</a>.</p>"#
        #expect(
            RichTextPlainForm.plainText(fromHTML: html)
                == "See the docs (https://example.com/docs).")
    }

    /// The absurdity that makes people stop trusting a paste. A notes app that linkifies
    /// a pasted url produces exactly this markup, so it is the common case, not the odd one.
    @Test(
        "never repeats a url that is already the link text",
        arguments: [
            #"<a href="https://example.com">https://example.com</a>"#,
            #"<a href="https://example.com/">https://example.com</a>"#,
            #"<a href="HTTPS://Example.com">https://example.com</a>"#,
        ])
    func linkTextIsTheURL(_ html: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "https://example.com")
    }

    @Test("does not repeat a url the text spells without its scheme")
    func linkTextIsTheURLWithoutScheme() {
        let html = #"<a href="https://example.com/pricing">example.com/pricing</a>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "example.com/pricing")
    }

    @Test("falls back to the url when the link has no text")
    func linkWithoutText() {
        let html = #"<p><a href="https://example.com/a"><img src="shot.png"></a></p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "https://example.com/a")
    }

    /// An address that means nothing once the page around it is gone is not worth the
    /// brackets: a `#section` anchor, a relative path, a handler.
    @Test(
        "drops a destination nobody could follow",
        arguments: [
            ##"<a href="#top">Back to top</a>"##,
            #"<a href="/docs/page">Back to top</a>"#,
            #"<a href="page.html">Back to top</a>"#,
            #"<a href="javascript:alert(1)">Back to top</a>"#,
            #"<a href="">Back to top</a>"#,
            "<a>Back to top</a>",
        ])
    func unfollowableLinks(_ html: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Back to top")
    }

    @Test("keeps a mailto behind a person's name, and not behind their address")
    func mailtoLinks() {
        let named = #"<a href="mailto:sam@example.com">Sam</a>"#
        #expect(RichTextPlainForm.plainText(fromHTML: named) == "Sam (mailto:sam@example.com)")
        let bare = #"<a href="mailto:sam@example.com">sam@example.com</a>"#
        #expect(RichTextPlainForm.plainText(fromHTML: bare) == "sam@example.com")
    }

    /// Link text is collected before it is decided what to do with it, so the spacing
    /// rules have to hold inside the collection too.
    @Test("keeps the spacing inside link text that carries its own formatting")
    func linkAroundInlineMarkup() {
        let split = #"<p><a href="https://example.com/x"><b>the</b> <i>docs</i></a></p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: split) == "the docs (https://example.com/x)")
        let trailing = #"<p><a href="https://example.com/x"><b>the</b> docs</a></p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: trailing) == "the docs (https://example.com/x)")
    }

    @Test("keeps a destination behind link text that is code")
    func linkAroundCode() {
        let html = #"<p><a href="https://example.com/x"><code>ls -la</code></a></p>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "ls -la (https://example.com/x)")
    }

    @Test("closes a link the document forgot to close")
    func unclosedLink() {
        let html = #"<p>See <a href="https://example.com/docs">the docs"#
        #expect(
            RichTextPlainForm.plainText(fromHTML: html)
                == "See the docs (https://example.com/docs)")
    }

    @Test("closes one link when another opens inside it")
    func nestedLink() {
        let html = #"<a href="https://a.example">one<a href="https://b.example">two</a>"#
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "one (https://a.example)two (https://b.example)")
    }

    /// An href arrives escaped, and a url with an unescaped `&amp;` in it is not a url.
    @Test("decodes the entities in an href")
    func linkWithEscapedQuery() {
        let html = #"<a href="https://example.com/s?q=a&amp;p=2">results</a>"#
        #expect(
            RichTextPlainForm.plainText(fromHTML: html) == "results (https://example.com/s?q=a&p=2)")
    }

    // MARK: - Line breaks

    @Test("turns block boundaries into single line breaks")
    func blockBreaks() {
        let html = "<p>one</p><p>two</p><div>three</div><br>four"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "one\ntwo\nthree\nfour")
    }

    /// Nesting is how blank lines pile up: a `</p></div></section>` asks for three breaks
    /// and must produce one.
    @Test("never piles up blank lines")
    func noPiledBreaks() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>a</p><br><br><br><p>b</p>") == "a\nb")
        let nested = "<section><div><p>a</p></div></section><section><div><p>b</p></div></section>"
        #expect(RichTextPlainForm.plainText(fromHTML: nested) == "a\nb")
    }

    @Test("starts and ends with content, never with whitespace")
    func noEdgeWhitespace() {
        let html = "\n  <div>\n  <p>  only  </p>\n  </div>\n  <br><br>\n"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "only")
    }

    @Test("gives a rule the gap of a section break")
    func horizontalRule() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>a</p><hr><p>b</p>") == "a\n\nb")
    }

    /// Pretty-printed HTML puts a newline and an indent between every tag. None of that
    /// is content, and treating it as content would double-space the whole paste.
    @Test("does not turn source indentation into line breaks")
    func prettyPrintedSource() {
        let html = """
            <div>
                <p>
                    A sentence
                    wrapped in the source.
                </p>
            </div>
            """
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "A sentence wrapped in the source.")
    }

    // MARK: - Code

    /// Code is whitespace. A snippet that arrives with its indentation collapsed is a
    /// snippet that has to be retyped.
    @Test("preserves a code block exactly, indentation and all")
    func preformatted() {
        let html = """
            <pre><code>func main() {
                print("hi")
            }
            </code></pre>
            """
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "func main() {\n    print(\"hi\")\n}")
    }

    @Test("keeps inline code inline")
    func inlineCode() {
        let html = "<p>Run <code>ls -la</code> now.</p>"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Run ls -la now.")
    }

    /// The one newline directly after `<pre>` is the source document's own formatting;
    /// HTML has always ignored it, and keeping it would open the paste with a blank line.
    @Test("drops the newline a source puts straight after the pre tag")
    func preLeadingNewline() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>x</p><pre>\nbody\n</pre>") == "x\nbody")
        #expect(RichTextPlainForm.plainText(fromHTML: "<pre>\r\nbody</pre>") == "body")
    }

    /// A snippet almost always ends in a newline of its own, and the block after it asks
    /// for a break as well. Two requests, one line: the newline already written counts.
    @Test("does not leave a blank line after a code block")
    func preTrailingNewline() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<pre>body\n</pre><p>next</p>") == "body\nnext")
    }

    /// The escaped form is how code with angle brackets actually reaches this function.
    @Test("gives escaped code back with its angle brackets")
    func escapedCodeInPre() {
        let html = "<pre><code>if (a &lt; b &amp;&amp; c &gt; d) { return &quot;ok&quot;; }</code></pre>"
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(out == "if (a < b && c > d) { return \"ok\"; }")
    }

    @Test("strips the highlighter's own markup from inside a code block")
    func highlightedCode() {
        let html = #"<pre><code><span class="kw">let</span> x = 1</code></pre>"#
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "let x = 1")
    }

    // MARK: - Entities

    @Test(
        "decodes the entities every document carries",
        arguments: [
            ("<p>Tom &amp; Jerry</p>", "Tom & Jerry"),
            ("<p>&lt;p&gt;</p>", "<p>"),
            ("<p>&quot;quoted&quot;</p>", "\"quoted\""),
            ("<p>it&#39;s</p>", "it's"),
            ("<p>it&#x27;s</p>", "it's"),
            ("<p>a&nbsp;b</p>", "a b"),
            ("<p>1&nbsp;&ndash;&nbsp;2</p>", "1 \u{2013} 2"),
            ("<p>caf&#233;</p>", "café"),
        ])
    func entities(_ html: String, _ expected: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == expected)
    }

    /// The case that catches every decoder written as a loop over its own output.
    /// `&amp;amp;` is the escaped form of the literal text `&amp;`, and a second pass
    /// would silently unescape what the author deliberately escaped.
    @Test("decodes an escaped entity exactly once")
    func doubleEscapedEntity() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>&amp;amp;</p>") == "&amp;")
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>&amp;lt;br&amp;gt;</p>") == "&lt;br&gt;")
    }

    /// An unrecognised reference is somebody's text: `AT&T` is a company, and `&foo;` is
    /// whatever the author meant by it.
    @Test(
        "leaves what is not an entity alone",
        arguments: [
            ("<p>AT&T</p>", "AT&T"),
            ("<p>&foo;</p>", "&foo;"),
            ("<p>Fish &amp chips</p>", "Fish &amp chips"),
            ("<p>a &amp;; b</p>", "a &; b"),
            ("<p>&#xD800;</p>", "&#xD800;"),
            ("<p>&#zz;</p>", "&#zz;"),
        ])
    func nonEntities(_ html: String, _ expected: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == expected)
    }

    /// A NUL or a bell character has no plain-text form and does real damage in a
    /// terminal, so it decodes to nothing.
    @Test("drops a control character somebody encoded")
    func controlCharacters() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<p>a&#0;b&#7;c</p>") == "abc")
    }

    @Test("decodes an entity in text that carries no tags")
    func entitiesWithoutTags() {
        #expect(RichTextPlainForm.plainText(fromHTML: "Tom &amp; Jerry") == "Tom & Jerry")
    }

    // MARK: - What must never be pasted

    /// A stylesheet or a script in a paste is worse than useless: it is somebody's whole
    /// afternoon spent deleting it out of a commit message.
    @Test("drops scripts and stylesheets entirely")
    func scriptsAndStyles() {
        let html = """
            <html><head><title>Note</title><style>p { color: red }</style></head>
            <body><p>Visible</p><script>if (a<b) { alert("<b>x</b>") }</script></body></html>
            """
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Visible")
    }

    @Test("drops a script that is never closed")
    func unclosedScript() {
        let html = "<p>Visible</p><script>var x = 1;"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Visible")
    }

    @Test("drops comments and doctypes")
    func commentsAndDoctypes() {
        let html = "<!DOCTYPE html><!-- private note --><p>Visible</p><!-- and this"
        #expect(RichTextPlainForm.plainText(fromHTML: html) == "Visible")
    }

    /// Word's own tags, and every custom element nobody could enumerate, are stripped
    /// like any other unknown inline tag once the document around them is recognisably
    /// HTML — which an end tag alone is enough to establish.
    ///
    /// The last line is the one input this file deliberately hands back as it came. A
    /// clip that is nothing but a single unrecognised open tag is likelier to be
    /// somebody's `Array<String>` than somebody's Word fragment, and losing a word of
    /// their code is the worse of the two mistakes.
    @Test("strips a tag no standard knows")
    func nonStandardTags() {
        let word = "<o:p>word's own tag</o:p><p>and a real one</p>"
        #expect(RichTextPlainForm.plainText(fromHTML: word) == "word's own tag\nand a real one")
        #expect(RichTextPlainForm.plainText(fromHTML: "<my-widget>x</my-widget>") == "x")
        #expect(RichTextPlainForm.plainText(fromHTML: "<o:p>only this") == "<o:p>only this")
    }

    @Test("drops an XML declaration")
    func processingInstruction() {
        #expect(RichTextPlainForm.plainText(fromHTML: "<?xml version=\"1.0\"?><p>Visible</p>") == "Visible")
    }

    // MARK: - Malformed input

    /// Unclosed tags, stray brackets, tags that close nothing. None of it may crash, and
    /// none of it may swallow the words after it.
    @Test(
        "keeps the words in malformed markup",
        arguments: [
            ("<p>Unclosed <b>bold text", "Unclosed bold text"),
            ("<p>Trailing bracket <b", "Trailing bracket"),
            ("<p>Trailing bracket <", "Trailing bracket <"),
            ("</p></div>after", "after"),
            ("<p>before<>after</p>", "before<>after"),
            ("<p =>value</p>", "value"),
            ("<p class=loud>bare attribute</p>", "bare attribute"),
            ("<p title='a > b'>quoted bracket</p>", "quoted bracket"),
            ("<p><br/><br />self closing</p>", "self closing"),
            ("<p>tag<b><i></b></i>soup</p>", "tagsoup"),
        ])
    func malformed(_ html: String, _ expected: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: html) == expected)
    }

    /// Prose that happens to contain a comparison is prose. The space after the `<` is
    /// what settles it, and a `>` is never special outside a tag.
    @Test(
        "reads a comparison in prose as prose",
        arguments: [
            "a < b",
            "5 < 10 and 20 > 15",
            "if (a < b && c > d)",
            "<3",
            "x <- rnorm(10)",
        ])
    func comparisonsInProse(_ text: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: text) == text)
    }

    /// A browser would read `Array<String>` as a tag and be right to; here that would
    /// lose a type parameter on the way into an editor. Input naming no HTML element is
    /// not HTML.
    @Test(
        "does not eat code that is shaped like markup",
        arguments: [
            "let names: Array<String> = []",
            "std::vector<std::pair<int, int>> v;",
            "template <typename T> struct Box {};",
            "for (i = 0; i<n; i++)",
        ])
    func codeShapedLikeMarkup(_ text: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: text) == text)
    }

    // MARK: - Degenerate input

    @Test("gives nothing back for nothing")
    func empty() {
        #expect(RichTextPlainForm.plainText(fromHTML: "") == "")
        #expect(RichTextPlainForm.plainText(fromHTML: "<p></p><div></div>") == "")
        #expect(RichTextPlainForm.plainText(fromHTML: "   \n\t ") == "   \n\t ")
    }

    /// Text with no markup in it is not reflowed at all. Its blank lines are the
    /// author's own, and HTML's whitespace model would eat them.
    @Test(
        "hands plain text back unchanged",
        arguments: [
            "hello",
            "Remember to email Priya about the invoice.",
            "one\n\n\nfour",
            "  leading and trailing  ",
            "\ttabbed\tcolumns\t",
            "• already a bullet",
            "https://example.com/a?b=c#d",
        ])
    func plainTextUnchanged(_ text: String) {
        #expect(RichTextPlainForm.plainText(fromHTML: text) == text)
    }

    /// A clip can be a whole document somebody selected with ⌘A. Nothing here may be
    /// quadratic in its length.
    @Test("handles an enormous clip")
    func enormousInput() {
        let items = (1...20_000).map { "<li>item number \($0) &amp; more</li>" }.joined()
        let out = RichTextPlainForm.plainText(fromHTML: "<h1>Big</h1><ul>\(items)</ul>")
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 20_002)
        #expect(lines.first == "Big")
        #expect(lines.last == "\u{2022} item number 20000 & more")
        #expect(!containsTagConstruct(out))
    }

    @Test("hands an enormous plain clip back untouched")
    func enormousPlainInput() {
        let text = String(repeating: "a line of ordinary prose\n", count: 100_000)
        #expect(RichTextPlainForm.plainText(fromHTML: text) == text)
    }

    // MARK: - The rule, made mechanical

    /// "Never HTML tags in a code editor", checked rather than argued.
    ///
    /// Every fixture in the corpus is markup, and none of them escapes a tag-shaped
    /// string — an escaped `&lt;b&gt;` is legitimate text and must survive, so it is
    /// tested separately and kept out of here, where it would be indistinguishable from
    /// a leak.
    @Test("leaves no tag anywhere in the output", arguments: Self.corpus)
    func noTagSurvives(_ html: String) {
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(!containsTagConstruct(out), "tag survived in: \(out)")
    }

    @Test("leaves no Markdown emphasis anywhere in the output", arguments: Self.corpus)
    func noMarkdownAdded(_ html: String) {
        let out = RichTextPlainForm.plainText(fromHTML: html)
        #expect(!out.contains("**"))
        #expect(!out.contains("#"))
        #expect(!out.contains("_"))
    }

    /// Truncating markup at every offset is how a fuzzer would find the input that
    /// crashes this, so it is done here instead.
    ///
    /// Checked against the looser rule, because a document cut through the middle of a
    /// tag ends in a `<` that is no longer a tag, and text is exactly what that should
    /// become. What must never get through is a whole one.
    @Test("survives every prefix of every fixture", arguments: Self.corpus)
    func everyPrefix(_ html: String) {
        for length in 0...html.count {
            let out = RichTextPlainForm.plainText(fromHTML: String(html.prefix(length)))
            #expect(!containsCompleteTag(out), "tag survived in prefix \(length): \(out)")
        }
    }

    /// One note of each kind the product promises to carry, written the way the editor
    /// that produces it writes it.
    static let corpus: [String] = [
        "",
        "<p></p>",
        "<h1>Shopping</h1><p>Before <b>Friday</b>.</p>",
        "<ul><li>Milk</li><li>Bread<ul><li>sourdough</li></ul></li></ul>",
        "<ol><li>one</li><li>two</li><li>three</li></ol>",
        """
        <ul class="checklist"><li class="checked">Passport</li>\
        <li class="unchecked">Adapter</li></ul>
        """,
        """
        <ul class="contains-task-list"><li class="task-list-item">\
        <input type="checkbox" checked> Ship it</li></ul>
        """,
        #"<p>See <a href="https://example.com/docs">the docs</a>.</p>"#,
        #"<p><a href="https://example.com">https://example.com</a></p>"#,
        "<pre><code>if (a &lt; b) { return 1; }</code></pre>",
        "<p>Run <code>swift build</code> first.</p>",
        "<blockquote><p>Quoted, at length.</p></blockquote>",
        "<table><tr><th>Name</th><th>Role</th></tr><tr><td>Sam</td><td>Design</td></tr></table>",
        "<!DOCTYPE html><html><head><title>Note</title><style>p{color:red}</style></head>"
            + "<body><h2>Trip</h2><p>Leaving Friday.</p>"
            + "<script>alert(\"<b>x</b>\")</script></body></html>",
        "<p>Unclosed <b>bold and <i>italic",
        "<p>Trailing bracket <b",
        "<div><p>a</p></div><br><br><div><p>b</p></div>",
        "<p =><b class=loud title='a > b'>attribute soup</b></p>",
        "<p>Tom &amp; Jerry, &#39;quoted&#39;, &nbsp;spaced.</p>",
        "<p>&amp;amp; stays escaped</p>",
        "<img src=\"shot.png\" alt=\"a screenshot\"><p>after an image</p>",
    ]
}

/// Whether anything in the output still looks like a tag: a `<` followed by something
/// that could open a tag name, or by a slash or a bang.
///
/// Deliberately looser than the parser, because the question here is not "would a browser
/// call this a tag" but "would a person reading a commit message call this a tag".
private func containsTagConstruct(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    for index in scalars.indices where scalars[index] == "<" {
        guard index + 1 < scalars.count else { continue }
        let next = scalars[index + 1]
        if next.properties.isAlphabetic || next == "/" || next == "!" { return true }
    }
    return false
}

/// Whether the output contains a *finished* tag: a name in brackets, opening or closing.
private func containsCompleteTag(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    for start in scalars.indices where scalars[start] == "<" {
        var index = start + 1
        if index < scalars.count, scalars[index] == "/" { index += 1 }
        guard index < scalars.count, scalars[index].properties.isAlphabetic else { continue }
        while index < scalars.count, scalars[index] != "<" {
            if scalars[index] == ">" { return true }
            index += 1
        }
    }
    return false
}
