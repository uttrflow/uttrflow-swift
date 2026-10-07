// The words of on-screen text with every secret-shaped run taken out.

extension SecretShapes {
    /// The text line by line, a secret-shaped run dropped and a line whose secret no single run carries emptied.
    public static func vocabulary(of text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard matches(String(line)) else { return String(line) }
                var kept = ""
                var droppedAny = false
                let runs = line.split(omittingEmptySubsequences: false, whereSeparator: \.isWhitespace)
                for (offset, run) in runs.enumerated() {
                    if offset > 0 { kept += " " }
                    if matches(String(run)) { droppedAny = true } else { kept += run }
                }
                return droppedAny ? kept : ""
            }
            .joined(separator: "\n")
    }
}
