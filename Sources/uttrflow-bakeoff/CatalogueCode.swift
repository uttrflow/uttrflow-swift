import UttrflowPredict

extension FixtureCatalogue {
    /// Lines of Swift, Python and TypeScript beneath a function the file already holds.
    static let code: [Scenario] = [
        Scenario(
            category: "code", name: "swift",
            situation: source(
                file: "Math.swift",
                above: "func add(a: Int, b: Int) -> Int {\n    return a + b\n}\n",
                recent: ["}", "    return a + b", "func add(a: Int, b: Int) -> Int {"]),
            cuts: .prose, determinacy: .code, band: 1...90, forbidden: ["return a + b"],
            known: ["func multiply(a: Int, b: Int) -> Int {", "let sum = add(a: 1, b: 2)", "struct Vector: Equatable {"],
            lines: [
                "func subtract(a: Int, b: Int) -> Int {", "    return a - b",
                Line("let total = add(a: 2, b: 3)", determinacy: .any),
                Line("guard let value else { return }", determinacy: .any),
                Line("struct Point: Equatable {", determinacy: .any), Line("import Foundation", determinacy: .any),
                Line("var count = 0", determinacy: .any),
            ]),
        Scenario(
            category: "code", name: "python",
            situation: source(
                file: "maths.py", above: "def add(a, b):\n    return a + b\n\n",
                recent: ["    return a + b", "def add(a, b):", "import json"]),
            cuts: .prose, determinacy: .code, band: 1...90, forbidden: ["return a + b"],
            known: ["def multiply(a, b):", "for item in items:", "if __name__ == '__main__':"],
            lines: [
                "def subtract(a, b):", "    return a - b", Line("import json", determinacy: .any),
                Line("for item in items:", determinacy: .any), Line("if __name__ == '__main__':", determinacy: .any),
                Line("class Point:", determinacy: .any), Line("total = add(2, 3)", determinacy: .any),
            ]),
        Scenario(
            category: "code", name: "typescript",
            situation: source(
                file: "maths.ts",
                above: "export function add(a: number, b: number): number {\n  return a + b;\n}\n",
                recent: ["}", "  return a + b;", "export function add(a: number, b: number): number {"]),
            cuts: .prose, determinacy: .code, band: 1...90, forbidden: ["return a + b;"],
            known: ["export function multiply(a: number, b: number): number {", "const sum = add(1, 2);"],
            lines: [
                "export function subtract(a: number, b: number): number {", "  return a - b;",
                Line("const total = add(2, 3);", determinacy: .any), Line("import { z } from 'zod';", determinacy: .any),
                Line("interface Point { x: number; y: number }", determinacy: .any), "export default subtract;",
                Line("let count = 0;", determinacy: .any),
            ]),
    ]

    /// A source file in an editor, with the function above the caret and its lines as the person's own.
    static func source(file: String, above: String, recent: [String]) -> GenerationSituation {
        GenerationSituation(
            application: "Editor", field: "Source", document: file, preceding: above, recentLines: recent,
            isMultiline: true)
    }
}
