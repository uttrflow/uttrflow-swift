/// The kind of place the words are going, which decides the formatter.
public enum Destination: String, Sendable, Equatable, CaseIterable, Codable {
    /// Word, Pages, Google Docs, Notes, TextEdit.
    case document
    /// Numbers, Excel, Google Sheets: one cell.
    case spreadsheet
    /// Postico, TablePlus, DataGrip, DBeaver, pgAdmin.
    case sqlEditor
    /// Xcode, Cursor, VS Code, Zed, JetBrains, terminals.
    case codeEditor
    /// Slack, WhatsApp, Telegram, Discord, Messages, Teams.
    case messaging
    /// Mail, Outlook, Gmail, Superhuman.
    case email
    /// Anything else.
    case plain
}
