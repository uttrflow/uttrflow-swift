import Foundation
import Testing

@testable import UttrflowCore

@Suite("Secret shape boundary checks", .bug(id: 5732))
struct SecretShapesMutationTests {
    private static let payload = Data((0..<63).map(UInt8.init)).base64EncodedString()

    @Test("rejects data URIs with invalid MIME components or parameters")
    func invalidMIME() {
        let invalidComponent = "data:ima:ge/png;base64,\(Self.payload)"
        let invalidParameter = "data:text/plain;charset;base64,\(Self.payload)"

        #expect(SecretShapes.matches(invalidComponent))
        #expect(SecretShapes.matches(invalidParameter))
    }

    @Test("rejects a data URI whose source attribute has mismatched quotes")
    func mismatchedSourceQuotes() {
        let text = "src=\"data:image/png;base64,\(Self.payload)'"

        #expect(SecretShapes.matches(text))
    }

    @Test("rejects a data URI whose CSS wrapper has mismatched quotes")
    func mismatchedCSSQuotes() {
        let text = "background:url(\"data:image/png;base64,\(Self.payload)')"

        #expect(SecretShapes.matches(text))
    }

    @Test("does not exempt joined words with an overlong numeric suffix")
    func joinedWordNumericSuffix() {
        #expect(SecretShapes.matches("northstar-riverbed-123abc"))
    }

    @Test("does not treat a quoted path with a generated-looking component as a secret")
    func quotedPath() {
        let token = "K9x$Qz7" + "Tr2Bn8LmVa"
        let path = "\"/Volumes/Backup Drive/photos/2026/\(token)\""

        #expect(!SecretShapes.matches(path))
    }

    @Test("does not treat an opaque known-scheme address as a secret")
    func knownURIScheme() {
        let address = "urn:example:" + "Q7Vn2mR8xL4pK9cD"

        #expect(!SecretShapes.matches(address))
    }

    @Test("ordinary short and non-ASCII text stays outside the entropy rule")
    func shortAndNonASCIITokens() {
        #expect(!SecretShapes.matches("x"))
        #expect(!SecretShapes.matches("☃"))
    }

    @Test(
        "ordinary developer paths, versions, images and packages stay visible",
        arguments: [
            "C:\\Users\\Avery\\Documents\\report2024.docx",
            "C:\\Users\\Avery Smith\\Documents\\report-2024.docx",
            "\"C:\\Users\\Avery Smith\\Documents\\report-2024.docx\"",
            "D:\\Work\\src\\main.swift",
            "C:\\ProgramData\\Acme\\config.json",
            "E:\\archive\\backup-2025-01-03.zip",
            "Z:\\Shared\\Design\\icon-2x.png",
            "C:/Users/Avery/Projects/app/build.gradle",
            "\\\\server\\share\\reports\\q3.xlsx",
            "\\\\fileserver\\team\\release\\app-v2.1.0.zip",
            "C:\\Users\\Avery\\AppData\\Local\\Temp\\build-4382",
            "D:\\Dev\\packages\\Foo\\1.0.0",
            "1.2.3-beta.4+build.567",
            "v2.4.0",
            "0.9.1-alpha",
            "2026.10.7",
            "3.14.159",
            "2.0.0-rc.1",
            "1.2.3+20261007",
            "2026-10-03",
            "1.2.3-dev.2026+ci.481",
            "10.12.0-preview.2",
            "registry.example.com/team/app:1.4.2-rc1",
            "ghcr.io/acme/desktop:2.1.0",
            "docker.io/library/redis:7.4.1",
            "localhost:5000/demo/web:v1.2.3",
            "registry.local:8443/platform/worker:2026.10.7",
            "ghcr.io/owner/tooling:0.2.0+build.17",
            "@babel/preset-env@7.23.0",
            "@types/node@22.7.4",
            "@scope/design-tokens@1.2.3-beta.4",
            "@company/build-tools@2026.10.7",
            "@astrojs/check@0.9.4",
            "@types/semver@7.5.8",
        ])
    func commonDeveloperReferencesRemainVisible(_ text: String) {
        #expect(!SecretShapes.matches(text), "\(text)")
        #expect(!SecretShapes.hasHighEntropyTokenByCharacter(text), "\(text)")
    }

    @Test("credential-looking container tags remain masked")
    func generatedContainerTagRemainsSecret() {
        let credential = "Q7vN4mR8xL2pK9cD"
        let reference = "ghcr.io/acme/desktop:\(credential)"

        #expect(SecretShapes.matches(reference))
        #expect(SecretShapes.hasHighEntropyTokenByCharacter(reference))
    }
}
