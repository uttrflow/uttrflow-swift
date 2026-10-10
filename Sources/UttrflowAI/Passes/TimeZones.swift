import UttrflowCore

/// The time zones a dictation names, as one table read for offsets ("UTC+5:30") and for the casing of zone names.
enum TimeZones {
    /// One zone: its abbreviation, the names it is written as, and whether an offset is counted from it.
    struct Zone {
        let abbreviation: String
        let names: [String]
        let countsOffsets: Bool

        init(_ abbreviation: String, _ names: [String], countsOffsets: Bool = false) {
            self.abbreviation = abbreviation
            self.names = names
            self.countsOffsets = countsOffsets
        }
    }

    /// Every zone the readers know; a regional name such as "Central time" is absent because it is also an ordinary phrase.
    static let table: [Zone] = [
        Zone("UTC", ["Coordinated Universal Time"], countsOffsets: true),
        Zone("GMT", ["Greenwich Mean Time"], countsOffsets: true),
        Zone("ET", ["Eastern time"]), Zone("PT", ["Pacific time"]),
        Zone("EST", ["Eastern Standard Time"]), Zone("EDT", ["Eastern Daylight Time"]),
        Zone("CST", ["Central Standard Time"]), Zone("CDT", ["Central Daylight Time"]),
        Zone("MST", ["Mountain Standard Time"]), Zone("MDT", ["Mountain Daylight Time"]),
        Zone("PST", ["Pacific Standard Time"]), Zone("PDT", ["Pacific Daylight Time"]),
        Zone("IST", ["India Standard Time", "Indian Standard Time"]),
        Zone("CET", ["Central European Time"]), Zone("BST", ["British Summer Time"]),
        Zone("JST", ["Japan Standard Time"]), Zone("AEST", ["Australian Eastern Standard Time"]),
    ]

    /// The zones an offset is counted from, keyed by each way they are heard: one word or spoken letters.
    static let offsetZones: [[String]: String] = Dictionary(
        uniqueKeysWithValues: table.filter(\.countsOffsets).flatMap { zone in
            let key = zone.abbreviation.lowercased()
            return [([key], zone.abbreviation), (key.map(String.init), zone.abbreviation)]
        })

    /// Each zone name's words, longest first, so "eastern standard time" wins over a shorter name inside it.
    private static let names: [[String]] = table.flatMap(\.names)
        .map { $0.split(separator: " ").map(String.init) }
        .sorted { $0.count > $1.count }

    /// The written form of every word in `shapes` that belongs to a zone name, keyed by its position.
    static func nameWords(in shapes: [WordShape]) -> [Int: String] {
        let keys = shapes.map(\.key)
        var written: [Int: String] = [:]
        var position = 0
        while position < keys.count {
            guard let name = names.first(where: { matches($0, at: position, keys: keys, shapes: shapes) })
            else {
                position += 1
                continue
            }
            for (offset, word) in name.enumerated() { written[position + offset] = word }
            position += name.count
        }
        return written
    }

    /// Whether `name` is heard at `position` with no punctuation inside it.
    private static func matches(
        _ name: [String], at position: Int, keys: [String], shapes: [WordShape]
    ) -> Bool {
        let end = position + name.count
        guard end <= keys.count, Array(keys[position..<end]) == name.map({ $0.lowercased() }) else {
            return false
        }
        return (position + 1..<end).allSatisfy { shapes[$0 - 1].suffix.isEmpty && shapes[$0].prefix.isEmpty }
    }
}
