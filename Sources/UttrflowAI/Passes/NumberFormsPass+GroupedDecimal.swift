extension NumberFormsPass {
    /// The whole value of a decimal the recogniser wrote with thousands groups, "2.5,000" for 2,500, or nil.
    static func scaledGroupedDecimal(_ key: String) -> Int? {
        let halves = key.split(separator: ".", omittingEmptySubsequences: false)
        guard halves.count == 2, !halves[0].isEmpty, halves[0].allSatisfy(isPlainDigit) else { return nil }
        let pieces = halves[1].split(separator: ",", omittingEmptySubsequences: false)
        let (fraction, groups) = (pieces[0], pieces.dropFirst())
        guard (1...3).contains(groups.count), groups.allSatisfy({ $0 == "000" }),
            (1...(3 * groups.count)).contains(fraction.count), fraction.allSatisfy(isPlainDigit)
        else { return nil }
        let places = 3 * groups.count
        return Int(halves[0] + fraction + String(repeating: "0", count: places - fraction.count))
    }

    private static func isPlainDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
