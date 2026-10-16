// The recorded differing cuts of the seam audit, and which of them may rise or fall.
package import Foundation

/// The cuts recorded as differing, which may fall and never rise, and those that depend on the macOS release.
package struct SeamBaseline: Codable, Equatable, Sendable {
    /// Cuts that only some macOS releases make differ, read on the named system.
    package struct OSDependent: Codable, Equatable, Sendable {
        /// The system the cuts were read on, as `ProcessInfo.operatingSystemVersionString` names it.
        package let system: String
        package let cuts: [String]

        package init(system: String, cuts: [String]) {
            self.system = system
            self.cuts = cuts
        }
    }

    package let cuts: [String]
    package let osDependent: OSDependent?
    package var total: Int { cuts.count }

    enum CodingKeys: String, CodingKey { case cuts, total, osDependent }

    package init(cuts: [String], osDependent: OSDependent? = nil) {
        self.cuts = cuts
        self.osDependent = osDependent
    }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cuts = try container.decode([String].self, forKey: .cuts)
        osDependent = try container.decodeIfPresent(OSDependent.self, forKey: .osDependent)
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(total, forKey: .total)
        try container.encode(cuts, forKey: .cuts)
        try container.encodeIfPresent(osDependent, forKey: .osDependent)
    }

    /// The keys that differ although neither list records them.
    package func risen(among keys: [String]) -> [String] {
        let tolerated = Set(cuts).union(osDependent?.cuts ?? [])
        return keys.filter { !tolerated.contains($0) }
    }

    /// This baseline with `keys` as its cuts, leaving out the OS-dependent ones, which stay as recorded.
    package func recording(_ keys: [String]) -> SeamBaseline {
        let dependent = Set(osDependent?.cuts ?? [])
        return SeamBaseline(cuts: keys.filter { !dependent.contains($0) }, osDependent: osDependent)
    }

    package static func read(from url: URL) throws -> SeamBaseline {
        try JSONDecoder().decode(SeamBaseline.self, from: Data(contentsOf: url))
    }

    package func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(self) + Data("\n".utf8)).write(to: url)
    }
}
