// Recognises common developer references which can resemble generated credentials.

/// Complete paths and versioned references commonly copied while programming.
package enum DeveloperReferenceShape {
    package static func matches(_ token: String) -> Bool {
        guard token.count <= 4096 else { return false }
        return windowsPath(token) || semanticVersion(token)
            || containerReference(token) || scopedPackage(token)
    }

    package static func isCompleteWindowsPath(_ text: String) -> Bool {
        text.count <= 4096 && !text.contains(where: \.isNewline) && windowsPath(text)
    }

    private static func windowsPath(_ token: String) -> Bool {
        if token.hasPrefix("\\\\") {
            let parts = token.dropFirst(2).split(whereSeparator: { $0 == "\\" || $0 == "/" })
            return parts.count >= 2 && parts.allSatisfy(validPathComponent)
        }
        guard token.count >= 4 else { return false }
        let chars = Array(token)
        guard chars[0].isASCII, chars[0].isLetter, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" else {
            return false
        }
        let parts = token.dropFirst(3).split(whereSeparator: { $0 == "\\" || $0 == "/" })
        return !parts.isEmpty && parts.allSatisfy(validPathComponent)
    }

    private static func validPathComponent(_ part: Substring) -> Bool {
        !part.isEmpty && !part.contains(where: { $0.isNewline || $0 == ":" || $0 == "*" || $0 == "?" })
    }

    private static func semanticVersion(_ token: String) -> Bool {
        let value = token.first == "v" || token.first == "V" ? String(token.dropFirst()) : token
        let buildSplit = value.split(separator: "+", omittingEmptySubsequences: false)
        guard buildSplit.count <= 2, buildSplit.allSatisfy({ !$0.isEmpty }) else { return false }
        if buildSplit.count == 2, !versionIdentifiers(buildSplit[1]) { return false }
        let releaseSplit = buildSplit[0].split(separator: "-", omittingEmptySubsequences: false)
        guard releaseSplit.count <= 2, releaseSplit.allSatisfy({ !$0.isEmpty }) else { return false }
        if releaseSplit.count == 2, !versionIdentifiers(releaseSplit[1]) { return false }
        let numbers = releaseSplit[0].split(separator: ".", omittingEmptySubsequences: false)
        return numbers.count >= 3 && numbers.allSatisfy(asciiDigits)
    }

    private static func versionIdentifiers(_ value: Substring) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private static func asciiDigits(_ value: Substring) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func containerReference(_ token: String) -> Bool {
        let path = token.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty }) else { return false }
        let image = path[path.count - 1].split(separator: ":", omittingEmptySubsequences: false)
        guard image.count == 2, validImageComponent(image[0]),
            semanticVersion(String(image[1]))
        else { return false }
        return path.dropLast().allSatisfy(validRegistryOrNamespace)
    }

    private static func validImageComponent(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }

    private static func validRegistryOrNamespace(_ part: Substring) -> Bool {
        let hostAndPort = part.split(separator: ":", omittingEmptySubsequences: false)
        guard hostAndPort.count <= 2, hostAndPort.allSatisfy(validImageComponent) else { return false }
        return hostAndPort.count == 1 || asciiDigits(hostAndPort[1])
    }

    private static func scopedPackage(_ token: String) -> Bool {
        guard token.first == "@", let slash = token.firstIndex(of: "/"),
            let versionMark = token[slash...].lastIndex(of: "@"), versionMark > slash
        else { return false }
        let scope = token[token.index(after: token.startIndex)..<slash]
        let name = token[token.index(after: slash)..<versionMark]
        let version = token[token.index(after: versionMark)...]
        return validPackagePart(scope) && validPackagePart(name) && semanticVersion(String(version))
    }

    private static func validPackagePart(_ part: Substring) -> Bool {
        !part.isEmpty && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}
