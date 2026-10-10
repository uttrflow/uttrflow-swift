/// Words that name or surround a credential in a field name or a credentials file, read from `credential-words.json`.
enum CredentialWords {
    /// Words an all-lowercase field name puts after a short code, as `otpcode` and `ssnfield` do.
    static let codeSuffixes = words(in: .codeSuffix)

    /// Words an all-lowercase field name puts before a short code, as `cardcvv`, `userotp` and `atmpin` do.
    static let codePrefixes = words(in: .codePrefix)

    /// The netrc directives that take one value.
    static let netrcValueDirectives = words(in: .netrcValueDirective)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("credential-words", schema: 1, from: .module, fallback: [])

    private static func words(in role: Role) -> Set<String> {
        Set(table.rows.filter { $0.roles.contains(role) }.map(\.id))
    }

    /// The lists a credential word belongs to.
    enum Role: String, Decodable, Sendable {
        case codeSuffix, codePrefix, netrcValueDirective
    }

    /// One credential word and the lists it belongs to.
    struct Row: DataTableRow {
        let id: String
        let roles: Set<Role>
    }
}
