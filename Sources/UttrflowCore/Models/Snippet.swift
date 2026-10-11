public import Foundation
public import struct Foundation.Date
public import struct Foundation.UUID

/// A phrase the user says and the text put in its place; kept as typed, with the matcher's form derived.
public struct Snippet: Sendable, Equatable, Identifiable, Codable {
    /// Stable identity across edits.
    public let id: UUID
    /// What the user says, as free text, because they say words and not `;addr`.
    public let trigger: String
    /// What is put in its place, verbatim, line breaks included.
    public let expansion: String
    /// When the user added it.
    public let created: Date
    /// How many dictations this snippet has fired in.
    public var timesUsed: Int
    /// When it last fired, or `nil` if never; shown beside ``created`` so the list says which rows earn it.
    public var lastUsed: Date?
    /// The bundle identifiers it fires in, as the person chose them; empty fires everywhere. See ``ApplicationScope``.
    public let applications: [String]

    /// A snippet with fresh counters unless told otherwise.
    public init(
        id: UUID = UUID(), trigger: String, expansion: String, created: Date,
        timesUsed: Int = 0, lastUsed: Date? = nil, applications: [String] = []
    ) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.created = created
        self.timesUsed = timesUsed
        self.lastUsed = lastUsed
        self.applications = ApplicationScope.normalised(applications)
    }

    private enum CodingKeys: String, CodingKey {
        case id, trigger, expansion, created, timesUsed, lastUsed, applications
    }

    /// Decodes a file from before scopes as a snippet that fires everywhere.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            trigger: try values.decode(String.self, forKey: .trigger),
            expansion: try values.decode(String.self, forKey: .expansion),
            created: try values.decode(Date.self, forKey: .created),
            timesUsed: try values.decode(Int.self, forKey: .timesUsed),
            lastUsed: try values.decodeIfPresent(Date.self, forKey: .lastUsed),
            applications: try values.decodeIfPresent([String].self, forKey: .applications) ?? [])
    }

    /// Writes the scope only when there is one, so an unconfined snippet's record keeps the shape every build reads.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(trigger, forKey: .trigger)
        try values.encode(expansion, forKey: .expansion)
        try values.encode(created, forKey: .created)
        try values.encode(timesUsed, forKey: .timesUsed)
        try values.encodeIfPresent(lastUsed, forKey: .lastUsed)
        if !applications.isEmpty { try values.encode(applications, forKey: .applications) }
    }

    /// The same snippet one use later, saturating at `Int.max` so a maxed-out counter cannot trap.
    public func used(at when: Date) -> Snippet {
        let (nextCount, overflowed) = timesUsed.addingReportingOverflow(1)
        return Snippet(
            id: id, trigger: trigger, expansion: expansion, created: created,
            timesUsed: overflowed ? Int.max : nextCount, lastUsed: when, applications: applications)
    }

    /// Whether this snippet fires where `bundleIdentifier` is in front.
    public func applies(in bundleIdentifier: String?) -> Bool {
        ApplicationScope.admits(applications, in: bundleIdentifier)
    }

    /// The trigger as the matcher sees it: in Latin letters as dictation writes it, lower-cased runs of letters and digits.
    public var triggerWords: [String] {
        WordTokens.words(LatinScript.enforced(trigger), .comparison).map { $0.lowercased() }
    }

    /// The spoken-command row heard in ordinary dictation that the trigger says, if any; the command wins over it.
    public var collidingCommand: SpokenCommand? {
        SpokenCommands.phrase(within: triggerWords)
    }

    /// Whether this snippet can ever fire: a wordless trigger matches everywhere, an empty expansion deletes.
    public var isUsable: Bool {
        // Checked directly, not through the tidier, because Core must not reach into UttrflowAI.
        !triggerWords.isEmpty
            && !body.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The expansion as it is written into a field: markers removed, escapes resolved, caret noted.
    public var body: SnippetBody { SnippetBody(parsing: expansion) }
}

/// A snippet expansion with its caret marker taken out; nothing outside the snippet store sees a marker.
public struct SnippetBody: Sendable, Equatable {
    /// Where the caret ends, written in a body; `\{caret}` writes the marker text itself.
    public static let caretMarker = "{caret}"
    /// The escape that makes the marker text literal.
    public static let escapedCaretMarker = "\\" + caretMarker

    /// The text inserted, without any marker.
    public let text: String
    /// UTF-16 units of ``text`` before the caret, or `nil` when the body has no marker; the first marker wins.
    public let caret: Int?

    /// Takes the markers out of `expansion`, keeping every other character as typed.
    public init(parsing expansion: String) {
        var text = ""
        var caret: Int?
        var rest = Substring(expansion)
        while !rest.isEmpty {
            if rest.hasPrefix(Self.escapedCaretMarker) {
                text += Self.caretMarker
                rest = rest.dropFirst(Self.escapedCaretMarker.count)
            } else if rest.hasPrefix(Self.caretMarker) {
                if caret == nil { caret = text.utf16.count }
                rest = rest.dropFirst(Self.caretMarker.count)
            } else if let first = rest.first {
                text.append(first)
                rest = rest.dropFirst()
            }
        }
        self.text = text
        self.caret = caret
    }
}
