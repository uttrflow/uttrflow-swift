/// HTML element names and how the plain form of copied HTML treats them, read from `html-elements.json`.
public enum HTMLElements {
    /// Every element HTML defines, obsolete ones included; generous, because a miss leaves tags showing.
    public static let names = Set(table.rows.map(\.id))

    /// Elements that never have content or an end tag, so hiding one hides only itself.
    public static let void = names(in: .void)

    /// Elements that start a new line in the plain form.
    public static let block = names(in: .block)

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("html-elements", schema: 1, from: .module, fallback: [])

    private static func names(in role: Role) -> Set<String> {
        Set(table.rows.filter { $0.roles.contains(role) }.map(\.id))
    }

    /// How an element is treated.
    enum Role: String, Decodable, Sendable {
        case void, block
    }

    /// One element name and the roles it has.
    struct Row: DataTableRow {
        let id: String
        let roles: Set<Role>
    }
}
