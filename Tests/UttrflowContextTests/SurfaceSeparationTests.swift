import Foundation
import Testing
import UttrflowCore

@testable import UttrflowContext

/// One field of an application family, whether it is the main surface, and the kind it is given today.
struct SurfaceFixture: CustomTestStringConvertible, Sendable {
    let file: String
    let destination: Destination
    let isPrimary: Bool
    /// What `DestinationFormatter.fieldKind(of:)` measured for this field.
    let measured: FieldKind

    init(_ name: String, _ destination: Destination, isPrimary: Bool, measured: FieldKind) {
        self.file = "surface-\(name).json"
        self.destination = destination
        self.isPrimary = isPrimary
        self.measured = measured
    }

    var testDescription: String { file }
}

/// How well role, subrole and label separate each family's main surface from its other fields.
///
/// See `Docs/surface-probe.md`.
@Suite("Surface separation")
struct SurfaceSeparationTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    static let fixtures: [SurfaceFixture] = [
        .init("editor-text", .codeEditor, isPrimary: true, measured: .primary),
        .init("editor-find", .codeEditor, isPrimary: false, measured: .oneLine),
        .init("editor-find-text-area", .codeEditor, isPrimary: false, measured: .primary),
        .init("editor-rename", .codeEditor, isPrimary: false, measured: .oneLine),
        .init("editor-command", .codeEditor, isPrimary: false, measured: .oneLine),
        .init("sql-query", .sqlEditor, isPrimary: true, measured: .primary),
        .init("sql-connection-host", .sqlEditor, isPrimary: false, measured: .oneLine),
        .init("sql-grid-cell", .sqlEditor, isPrimary: false, measured: .oneLine),
        .init("sql-filter", .sqlEditor, isPrimary: false, measured: .oneLine),
        .init("chat-composer", .messaging, isPrimary: true, measured: .primary),
        .init("chat-search", .messaging, isPrimary: false, measured: .oneLine),
        .init("chat-thread-title", .messaging, isPrimary: false, measured: .oneLine),
        .init("chat-channel-topic", .messaging, isPrimary: false, measured: .primary),
        .init("mail-body", .email, isPrimary: true, measured: .primary),
        .init("mail-recipient", .email, isPrimary: false, measured: .oneLine),
        .init("mail-subject", .email, isPrimary: false, measured: .oneLine),
        .init("mail-search", .email, isPrimary: false, measured: .oneLine),
        .init("terminal-shell", .terminal, isPrimary: true, measured: .primary),
        .init("terminal-tab-title", .terminal, isPrimary: false, measured: .oneLine),
        .init("terminal-find", .terminal, isPrimary: false, measured: .oneLine),
        .init("terminal-settings-search", .terminal, isPrimary: false, measured: .oneLine),
    ]

    /// The context the focused-window read banks for the fixture's field: its names, line mode and label.
    private static func context(_ fixture: SurfaceFixture) throws -> AppContext {
        let snapshot = try AccessibilitySnapshot.decode(
            Data(contentsOf: directory.appending(path: fixture.file)))
        let names = FocusedFieldRead.names(
            of: snapshot.focused, in: WindowReplayTree(window: snapshot.focused))
        let answered = snapshot.focused.attributes["AXMultiline"]?.fieldAnswer.integer.map { $0 != 0 }
        return AppContext(
            documentName: snapshot.windowTitle, accessibilityRole: names.role,
            accessibilitySubrole: names.subrole,
            isMultiline: MacContextEngine.isMultiline(answered, role: names.role), fieldLabel: names.label)
    }

    private static func kind(_ fixture: SurfaceFixture) throws -> FieldKind {
        let app = try context(fixture)
        return DestinationFormatter.fieldKind(
            of: Situation(app: app, insertion: app.insertionPoint, destination: fixture.destination))
    }

    @Test("gives each field the kind the probe measured", arguments: fixtures)
    func measuredKind(_ fixture: SurfaceFixture) throws {
        #expect(try Self.kind(fixture) == fixture.measured)
    }

    @Test func noPrimarySurfaceIsTakenForAnotherField() throws {
        for fixture in Self.fixtures where fixture.isPrimary {
            #expect(try Self.kind(fixture) == .primary, "\(fixture.file)")
        }
    }

    /// Secondary fields resolved as secondary, per family, as `Docs/surface-probe.md` reports them.
    @Test func secondaryFieldsResolvedPerFamily() throws {
        var resolved: [Destination: [Bool]] = [:]
        for fixture in Self.fixtures where !fixture.isPrimary {
            resolved[fixture.destination, default: []].append(try Self.kind(fixture) != .primary)
        }
        let counts = resolved.mapValues { [$0.filter { $0 }.count, $0.count] }
        #expect(
            counts == [
                .codeEditor: [3, 4], .sqlEditor: [3, 3], .messaging: [2, 3], .email: [3, 3],
                .terminal: [3, 3],
            ])
    }

    /// Every field the role leaves on the main surface names itself, so its label could separate it.
    @Test func everySecondaryFieldTheRoleMissesCarriesALabel() throws {
        for fixture in Self.fixtures where !fixture.isPrimary {
            let app = try Self.context(fixture)
            guard app.accessibilityRole == "AXTextArea" else { continue }
            #expect(app.fieldLabel != nil, "\(fixture.file)")
        }
    }

    /// A search field declared by its subrole alone is resolved as a one-line field, not as a search.
    @Test func aSearchSubroleIsNotReadAsASearch() throws {
        let searches = try Self.fixtures.filter {
            try Self.context($0).accessibilitySubrole == "AXSearchField"
        }
        #expect(searches.count == 5)
        for fixture in searches {
            #expect(try Self.kind(fixture) == .oneLine, "\(fixture.file)")
        }
    }

    @Test func everySurfaceFixtureIsMeasured() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path())
            .filter { $0.hasPrefix("surface-") }
        #expect(Set(files) == Set(Self.fixtures.map(\.file)))
    }
}
