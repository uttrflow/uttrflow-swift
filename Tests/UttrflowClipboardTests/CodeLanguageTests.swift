// Tests for language detection.

import Testing

@testable import UttrflowClipboard

@Suite("Which language a code clip is written in")
struct CodeLanguageTests {
    // MARK: - Nothing to go on

    /// `nil` is the default answer, and these are the shapes that have to reach it.
    @Test(
        "says nothing when there is nothing to say",
        arguments: [
            "",
            "   \n\t ",
            "hello",
            "Uttrflow",
            "I told them {name} would be there, and it was",
            "The config uses {} for an empty object; that surprised me.",
            "x = 1",
            "let x = 1",
            "return true",
            "foo()",
            "{}",
            "[]",
        ])
    func unknown(_ text: String) {
        #expect(CodeLanguage.detect(text) == nil)
    }

    // MARK: - Swift against TypeScript

    /// The confusion that actually happens, written the way each language is really written.
    @Test("calls Swift Swift")
    func swiftCode() {
        let text = """
            struct Clip: Identifiable {
                let id: UUID
                var title: String

                func summary() -> String {
                    "\\(title) — \\(id)"
                }
            }
            """
        #expect(CodeLanguage.detect(text) == .swift)
    }

    @Test("calls TypeScript TypeScript")
    func typeScriptCode() {
        let text = """
            export interface Clip {
              id: string;
              title: string;
            }

            export function summary(clip: Clip): string {
              return `${clip.title} — ${clip.id}`;
            }
            """
        #expect(CodeLanguage.detect(text) == .typescript)
    }

    /// A `guard`, an interpolation and a trailing closure, with no house style to lean on.
    @Test("calls a Swift extension Swift")
    func swiftExtension() {
        let text = """
            extension ClipboardStore {
                func pinned() async throws -> [Clip] {
                    guard let all = try? await load() else { return [] }
                    return all.filter { $0.isPinned }
                }
            }
            """
        #expect(CodeLanguage.detect(text) == .swift)
    }

    // MARK: - Python against Ruby

    /// The colon after `def` is most of the difference, so the same function is written twice.
    @Test("calls Python Python")
    func pythonCode() {
        let text = """
            def greet(name):
                if not name:
                    return "hello"
                elif name.isupper():
                    return f"HELLO {name}"
                return f"hello {name}"
            """
        #expect(CodeLanguage.detect(text) == .python)
    }

    @Test("calls Ruby Ruby")
    func rubyCode() {
        let text = """
            def greet(name)
              if name.nil?
                puts "hello"
              elsif name.empty?
                puts "hello there"
              end
            end
            """
        #expect(CodeLanguage.detect(text) == .ruby)
    }

    @Test("does not mistake a Python import for a Swift one")
    func pythonImports() {
        let text = """
            from pathlib import Path
            import json

            data = json.loads(Path("clips.json").read_text())
            for clip in data:
                print(clip["text"])
            """
        #expect(CodeLanguage.detect(text) == .python)
    }

    // MARK: - JSON against a JavaScript object literal

    /// A parser settles this one: quoted keys parse, unquoted keys do not.
    @Test("calls a JSON document JSON")
    func jsonDocument() {
        #expect(CodeLanguage.detect(#"{"name": "uttrflow", "retries": 3}"#) == .json)
        #expect(CodeLanguage.detect(#"[{"id": 1}, {"id": 2}]"#) == .json)
        #expect(
            CodeLanguage.detect(
                """
                {
                  "retention": { "days": 30 },
                  "pinned": ["/pgprod", "/token"]
                }
                """) == .json)
    }

    /// An object literal with unquoted keys is not JSON, and alone is not enough to be anything else.
    @Test("does not call a bare object literal JSON")
    func bareObjectLiteral() {
        #expect(CodeLanguage.detect("{ name: \"uttrflow\", retries: 3 }") == nil)
    }

    /// The same literal with JavaScript around it, which is what settles it.
    @Test("calls a CommonJS module JavaScript")
    func commonJSModule() {
        let text = """
            const config = { name: "uttrflow", retries: 3 };
            module.exports = config;
            """
        #expect(CodeLanguage.detect(text) == .javascript)
    }

    @Test("calls a require-and-export script JavaScript")
    func javaScriptRequire() {
        let text = """
            const fs = require("fs");

            function load(path) {
              return JSON.parse(fs.readFileSync(path, "utf8"));
            }

            module.exports = { load };
            """
        #expect(CodeLanguage.detect(text) == .javascript)
    }

    // MARK: - SQL

    /// Case is not evidence: the same query three ways must come out the same.
    @Test(
        "calls SQL SQL whatever the case",
        arguments: [
            "SELECT * FROM clips WHERE pinned = true;",
            "select * from clips where pinned = true;",
            "SeLeCt * FrOm clips WhErE pinned = true;",
            "SELECT id, text FROM clips ORDER BY copied_at DESC LIMIT 20",
            """
            CREATE TABLE clips (
              id UUID PRIMARY KEY,
              text TEXT NOT NULL
            );
            """,
            "INSERT INTO clips (id, text) VALUES (gen_random_uuid(), 'hi');",
            "UPDATE clips SET pinned = true WHERE id = $1;",
            "SELECT name FROM users",
        ])
    func sql(_ text: String) {
        #expect(CodeLanguage.detect(text) == .sql)
    }

    /// `select` and `from` are ordinary English; articles are the giveaway.
    @Test(
        "does not call an English sentence SQL",
        arguments: [
            "Select an item from the list below",
            "Please select the region from the dropdown and click Save.",
            "I'll select a few photos from the album later",
        ])
    func sqlLookalikes(_ text: String) {
        #expect(CodeLanguage.detect(text) == nil)
    }

    // MARK: - Shell

    @Test("calls a shebang script by its interpreter")
    func shebangs() {
        #expect(CodeLanguage.detect("#!/bin/bash\nls -la\n") == .shell)
        #expect(CodeLanguage.detect("#!/bin/sh\nls\n") == .shell)
        #expect(CodeLanguage.detect("#!/usr/bin/env zsh\nprint hi\n") == .shell)
        #expect(CodeLanguage.detect("#!/usr/bin/env python3\nprint('hi')\n") == .python)
        #expect(CodeLanguage.detect("#!/usr/bin/env ruby\nputs 'hi'\n") == .ruby)
        #expect(CodeLanguage.detect("#!/usr/bin/env node\nconsole.log('hi')\n") == .javascript)
        #expect(CodeLanguage.detect("#!/usr/bin/env swift\nprint(\"hi\")\n") == .swift)
    }

    /// An interpreter with no chip falls through rather than being forced into the nearest one.
    @Test("does not force an unknown interpreter into a language")
    func unknownShebang() {
        #expect(CodeLanguage.detect("#!/usr/bin/env perl\nmy $x = 1;\n") == nil)
    }

    /// Most copied shell has no shebang, having been copied out of the middle of a file.
    @Test("calls a shell script shell without a shebang")
    func shellWithoutShebang() {
        let text = """
            set -euo pipefail

            for file in *.txt; do
              echo "processing $file"
            done
            """
        #expect(CodeLanguage.detect(text) == .shell)
    }

    @Test("calls a shell function shell")
    func shellFunction() {
        let text = """
            deploy() {
              if [[ -z "$1" ]]; then
                echo "usage: deploy <env>" >&2
                exit 1
              fi
              export TARGET="$1"
            }
            """
        #expect(CodeLanguage.detect(text) == .shell)
    }

    // MARK: - Markdown

    /// A fence says what a region is in, not the clip, and is asserted rather than observed.
    @Test("does not take a fence at its word")
    func fencedBlock() {
        let markdown = """
            Here is how you make a clip:

            ```swift
            let clip = Clip(text: "hi", kind: .text, copiedAt: .now)
            ```

            That is all there is to it.
            """
        #expect(CodeLanguage.detect(markdown) == nil)
    }

    @Test("does not label a bare fenced block either")
    func bareFencedBlock() {
        let text = """
            ```python
            def greet(name):
                return f"hello {name}"
            ```
            """
        #expect(CodeLanguage.detect(text) == nil)
    }

    // MARK: - Two languages at once

    /// HTML with a script in it is HTML; the script is a region inside the document.
    @Test("calls a page with inline script HTML")
    func htmlWithInlineScript() {
        let text = """
            <!DOCTYPE html>
            <html>
              <body>
                <div id="app">Loading…</div>
                <script>
                  const app = document.getElementById("app");
                  app.textContent = "Ready";
                </script>
              </body>
            </html>
            """
        #expect(CodeLanguage.detect(text) == .html)
    }

    @Test("calls a markup fragment HTML")
    func htmlFragment() {
        let text = """
            <section class="clips">
              <ul>
                <li><a href="/clip/1">First</a></li>
              </ul>
            </section>
            """
        #expect(CodeLanguage.detect(text) == .html)
    }

    // MARK: - The rest of the set

    @Test("calls CSS CSS")
    func css() {
        let text = """
            .clip-row {
              display: flex;
              padding: 4px 8px;
              font-size: 13px;
            }

            .clip-row:hover {
              background-color: var(--selection);
            }
            """
        #expect(CodeLanguage.detect(text) == .css)
    }

    @Test("calls Go Go rather than Swift")
    func go() {
        let text = """
            package main

            func Load(path string) ([]Clip, error) {
                data, err := os.ReadFile(path)
                if err != nil {
                    return nil, err
                }
                return parse(data)
            }
            """
        #expect(CodeLanguage.detect(text) == .go)
    }

    @Test("calls Rust Rust rather than Swift")
    func rust() {
        let text = """
            pub fn summary(clip: &Clip) -> String {
                let mut out = String::new();
                match clip.alias {
                    Some(ref a) => out.push_str(a),
                    None => out.push_str(&clip.text),
                }
                out
            }
            """
        #expect(CodeLanguage.detect(text) == .rust)
    }

    @Test("calls Java Java")
    func java() {
        let text = """
            public class ClipStore {
                private final List<Clip> clips = new ArrayList<>();

                @Override
                public String toString() {
                    System.out.println(clips.size());
                    return "ClipStore";
                }
            }
            """
        #expect(CodeLanguage.detect(text) == .java)
    }

    // MARK: - Size

    /// A minified bundle is one enormous line, and only the first few thousand characters are read.
    @Test("reads a long minified line without choking on it")
    func minifiedLine() {
        let chunk = "function n\(0)(e){return e.map(function(r){return r*2})}"
        let text =
            "var t=require(\"./util\");"
            + String(repeating: chunk, count: 4_000)
            + "module.exports=t;"
        #expect(text.count > 100_000)
        #expect(CodeLanguage.detect(text) == .javascript)
    }

    /// The same size, but prose. Length is not evidence.
    @Test("does not label a very long paragraph")
    func longProse() {
        let text = String(
            repeating: "The clipboard is a strange place to keep things, and yet we all do. ",
            count: 2_000)
        #expect(CodeLanguage.detect(text) == nil)
    }

    // MARK: - Chips

    /// Only the three names anybody abbreviates get abbreviated.
    @Test("abbreviates only the names that are habitually abbreviated")
    func chips() {
        #expect(CodeLanguage.javascript.chip == "js")
        #expect(CodeLanguage.typescript.chip == "ts")
        #expect(CodeLanguage.shell.chip == "sh")
        #expect(CodeLanguage.swift.chip == "swift")
        #expect(CodeLanguage.sql.chip == "sql")
        for language in CodeLanguage.allCases {
            #expect(!language.chip.isEmpty)
        }
    }

    /// The raw values are written to disk with every clip, so renaming a case must be deliberate.
    @Test("keeps its raw values stable")
    func rawValues() {
        #expect(CodeLanguage.allCases.count == 13)
        #expect(CodeLanguage(rawValue: "typescript") == .typescript)
        #expect(CodeLanguage(rawValue: "ts") == nil)
    }
}
