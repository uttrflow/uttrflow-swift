import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("Code-shaped clipboard text")
struct CodeShapesTests {
    @Test("recognises the reported markup, configuration, Markdown and statement forms")
    func namedForms() {
        let examples = [
            "<!DOCTYPE html>", "<div class=\"card\">Hello</div>", "<ul><li>First</li></ul>",
            "<img src=\"image.png\">", "<form><input></form>", "<head></head>",
            "app: uttrflow\nversion: 1.2.3", "debug: true\nport: 8080", "name: \"clip\"\ncount: 4",
            "name: Ada\ndate: today", "name = Ada\ndate = today", "name = \"clip\"\ncount = 4",
            "host = \"localhost\"\nport = 8080", "enabled = true\nretries = 3",
            "[server]\nhost = \"localhost\"\nport = 8080", "# Release notes", "## Build status",
            "| Name | Value |\n| --- | --- |\n| retries | 3 |", "```swift\nlet count = 1\n```",
            "x := make(map[string]int)", "defer wg.Done()", "List<String> xs = new ArrayList<>();",
            "$x = $_GET['id']", "cat a | sort | uniq -c", "export PATH=\"$HOME/bin:$PATH\"",
            "items.each do |item|\n  puts item\nend", "#app { color: red; }",
        ]
        let missed = examples.filter { !CodeShapes.matches($0) }
        #expect(missed.isEmpty, "not recognised: \(missed)")
    }

    @Test("The CSS rule scanner accepts selector lists and respects the full input boundary")
    func cssRuleBoundaries() {
        #expect(CodeShapes.isCSSRule(in: " #app, #panel { color: red; } "))
        #expect(!CodeShapes.isCSSRule(in: "#app { color: red; } trailing"))
        #expect(!CodeShapes.isCSSRule(in: "#app { color: red; "))
        #expect(!CodeShapes.isCSSRule(in: "#app { color: ; }"))
    }

    @Test("keeps diagnostics and questions about calls as prose")
    func diagnosticAndProseControls() {
        let examples = [
            "npm ERR! code ENOENT",
            "Traceback (most recent call last):\n  File \"app.py\", line 4, in run\n    raise ValueError()\nValueError: bad input",
            "can you check the function foo() in utils?",
            "I wrote the word function in my notes.",
            "The div element wraps the page content.",
            "The heading says # Release today.",
            "From: Ada\nTo: Grace",
            "The profile name is Ada and the date is today.",
            "Please export the final report tomorrow.",
            "The cat will sort the papers and leave the unique ones.",
            "We need to defer the review until Monday.",
            "The list of strings is ready for the meeting.",
            "A path can look like src/App.swift:42.",
            "The server returned code ENOENT after the restart.",
            "The traceback explains where the request failed.",
            "I asked whether name() belongs in the example.",
            "Please review the HTML form before publishing.",
            "The configuration name is app and its version is current.",
            "A table with pipes is hard to read in chat.",
            "She said do this now and end the call later.",
            "The CSS id rule is described below.",
            "Sort by name and export the selected rows.",
        ]
        let falsePositives = examples.filter { CodeShapes.matches($0) }
        #expect(falsePositives.isEmpty, "classified as code: \(falsePositives)")
    }

    @Test("classifies at least 24 snippets in each supported language family")
    func languageCorpus() {
        let missed = Self.languageSamples.filter { !CodeShapes.matches($0.1) }
        #expect(Self.languageSamples.count == 312)
        #expect(missed.isEmpty, "missed \(missed.count)/312: \(missed.prefix(8))")
    }

    private static let languageSamples: [(String, String)] = {
        let names = ["alpha", "bravo", "charlie", "delta"]
        let templates: [(String, [String])] = [
            (
                "Swift",
                [
                    "func {name}() {}", "func {name}() -> Int { 1 }", "struct {name} { let value = 1 }",
                    "let {name} = true;", "if (ready) { run() }", "public func {name}() { return }",
                ]
            ),
            (
                "Python",
                [
                    "def {name}():\n    return 1", "class {name}:\n    pass", "if ready:\n    run()\n",
                    "for {name} in values:\n    print({name})",
                    "with open(\"{name}\") as file:\n    read(file)",
                    "try:\n    run()\nexcept ValueError:\n    pass",
                ]
            ),
            (
                "Ruby",
                [
                    "def {name}\n  puts 1\nend", "class {name}\n  def run\n    true\n  end\nend",
                    "items.each do |{name}|\n  puts {name}\nend", "if ready\n  run\nend",
                    "module {name}\n  VALUE = 1\nend", "def {name}(value)\n  value.to_s\nend",
                ]
            ),
            (
                "JavaScript",
                [
                    "const {name} = items.map(item => item + 1);", "function {name}() { return true; }",
                    "module.exports = {name};", "if (ready) { run(); }", "class {name} { run() {} }",
                    "const {name} = require(\"module\");",
                ]
            ),
            (
                "TypeScript",
                [
                    "const {name}: number = 1;", "interface {name} { id: string; }",
                    "type {name} = string | number;",
                    "function {name}(value: string): string { return value; }",
                    "export const {name} = (value: number): number => value;",
                    "class {name} { value: string = \"x\"; }",
                ]
            ),
            (
                "JSON",
                [
                    "{\"{name}\": 1}", "[{\"{name}\": true}]", "{\"{name}\": [1, 2]}",
                    "{\"item\": {\"name\": \"{name}\"}}", "[{\"name\": \"{name}\"}]",
                    "{\"enabled\": false, \"name\": \"{name}\"}",
                ]
            ),
            (
                "SQL",
                [
                    "SELECT id FROM {name};", "UPDATE {name} SET active = true;",
                    "DELETE FROM {name} WHERE id = 1;", "INSERT INTO {name} (id) VALUES (1);",
                    "SELECT * FROM {name} WHERE active = true", "CREATE TABLE {name} (id INT);",
                ]
            ),
            (
                "Shell",
                [
                    "cat {name}.txt | sort | uniq -c", "export {name}=true", "git status --short",
                    "grep {name} file.txt", "mkdir -p {name}/cache", "npm run {name}",
                ]
            ),
            (
                "HTML",
                [
                    "<!doctype html><html><body><div id=\"{name}\"></div></body></html>",
                    "<{name}></{name}>", "<form><input name=\"{name}\"></form>",
                    "<ul><li>{name}</li></ul>", "<head><title>{name}</title></head>",
                    "<img src=\"{name}.png\">",
                ]
            ),
            (
                "CSS",
                [
                    "#{name} { color: red; }", "#tile-{name} { display: block; }",
                    "#row-{name} { margin: 0; }", "#panel-{name} { padding: 4px; }",
                    "#view-{name} { background: white; }", "#card-{name} { border: 0; }",
                ]
            ),
            (
                "Go",
                [
                    "func {name}() {}", "value := make(map[string]int)", "defer wg.Done()",
                    "package {name}\nfunc Run() {}", "if err != nil { return err }",
                    "for _, {name} := range items { run({name}) }",
                ]
            ),
            (
                "Rust",
                [
                    "fn {name}() -> i32 { 1 }", "let {name} = Some(1);",
                    "match value { Some(x) => x, None => 0 }",
                    "pub struct {name} { value: i32 }", "use std::collections::HashMap;",
                    "fn {name}(x: i32) { println!(\"{}\", x); }",
                ]
            ),
            (
                "Java",
                [
                    "List<String> {name} = new ArrayList<>();", "public class {name} {}",
                    "public static void {name}() {}", "if (ready) { run(); }", "return new {name}();",
                    "import java.util.List;\nclass {name} {}",
                ]
            ),
        ]
        let samples = templates.flatMap { language, variants in
            variants.flatMap { template in
                names.map { (language, template.replacingOccurrences(of: "{name}", with: $0)) }
            }
        }
        return samples
    }()
}
