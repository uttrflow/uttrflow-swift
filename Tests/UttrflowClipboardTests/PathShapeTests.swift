// Tests for file-path detection.

import Foundation
import Testing

@testable import UttrflowClipboard

/// A path is a shape almost anything can wear, so the tests that matter are about what it must not take.
@Suite("K5 · a file or folder path")
struct PathShapeTests {
    @Test(
        "paths people actually copy",
        arguments: [
            "/Users/naveen/Desktop/notes.txt",
            "~/Desktop/projects/uttrflow",
            "~/Library/Application Support/Uttrflow/clipboard.v1.json",
            "./Scripts/coverage.sh",
            "~/Desktop/My Notes.txt",
            "../Sources/UttrflowUX/PanelResults.swift",
            "/usr/local/bin",
            "/Users/naveen/Desktop/a-file_with.punctuation(2).txt",
        ])
    func paths(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .filePath)
    }

    /// Things people copy all day that a slash-hunting detector would claim.
    @Test(
        "things that merely contain a slash",
        arguments: [
            "2026/08/24",
            "1/2",
            "and/or",
            "he said yes/no and left",
            "The file is at /Users/naveen/notes.txt somewhere",
            "cat /etc/hosts | grep localhost",
            "//",
            "/",
            "~",
            "N/A",
        ])
    func notPaths(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) != .filePath)
    }

    /// One space is a folder name; a flag, or a second space, is a command.
    @Test("one space is a folder name, an argument is a command")
    func spacesAreJudged() {
        #expect(ClipKindDetector.kind(of: "~/Desktop/My Notes.txt") == .filePath)
        #expect(ClipKindDetector.kind(of: "./deploy.sh --force") != .filePath)
        #expect(ClipKindDetector.kind(of: "/usr/bin/env ruby x.rb") != .filePath)
    }

    /// A path with a newline is a list of paths or a paragraph, and either way not a file.
    @Test("several paths at once are not one path")
    func manyPathsAreNotOne() {
        #expect(ClipKindDetector.kind(of: "/usr/bin\n/usr/local/bin") != .filePath)
    }

    /// `file://` is neither a link nor a path; what the clip holds is the URL.
    @Test("a file URL is not claimed as a path")
    func fileURLsAreNotPaths() {
        #expect(ClipKindDetector.kind(of: "file:///Users/naveen/notes.txt") == .text)
    }

    /// A credential is masked whatever else it looks like.
    @Test("a secret is still a secret")
    func secretsWin() {
        #expect(ClipKindDetector.kind(of: "postgres://user:pw@host:5432/db") != .filePath)
    }

    /// Read character by character, like code, because a mistyped path fails like a missing file.
    @Test("a path is set in a monospaced face")
    func pathsAreMonospaced() {
        #expect(ClipKindDetector.kind(of: "/usr/local/bin") == .filePath)
    }
}
