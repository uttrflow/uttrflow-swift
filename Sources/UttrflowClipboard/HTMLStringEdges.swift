extension String {
    func trimmedEdges() -> String {
        String(trimmedTrailing().unicodeScalars.drop(while: \.properties.isWhitespace))
    }

    func trimmingTrailingSpace() -> String {
        var copy = self
        while copy.hasSuffix(" ") { copy.removeLast() }
        return copy
    }

    func trimmedTrailing() -> String {
        var scalars = unicodeScalars[...]
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }

    /// The scheme of an absolute url; hand-written because `URL` accepts `page.html` as a url.
    func urlScheme() -> String? {
        var scheme = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if scalar == ":" {
                return scheme.isEmpty ? nil : String(scheme).lowercased()
            }
            guard
                scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
                    || "+-.".unicodeScalars.contains(scalar)
            else { return nil }
            scheme.append(scalar)
        }
        return nil
    }
}
