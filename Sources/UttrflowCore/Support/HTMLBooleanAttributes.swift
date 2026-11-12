/// HTML attributes a tag holds by name alone, with no value, read from `html-boolean-attributes.json`.
package enum HTMLBooleanAttributes {
    /// Every attribute whose presence is its value, as `disabled` in `<input disabled>`.
    package static let names = Set(table.rows.map(\.id))

    /// The bundled table; see `Docs/data-tables.md`.
    static let table = DataTable<Row>.load("html-boolean-attributes", schema: 1, from: .module, fallback: [])

    /// One attribute name.
    struct Row: DataTableRow {
        let id: String
    }
}
