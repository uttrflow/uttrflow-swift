"""Proves measurement names belong to each tool's registered root commands."""
import tempfile
import unittest
from pathlib import Path

import measure_commands_audit as audit


class RegisteredCommandTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="command-registry-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.sources = self.root / "Sources" / "uttrflow-dev"
        self.sources.mkdir(parents=True)
        self.write("Root.swift", '''@main
struct Root: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-dev", subcommands: [Bench.self, Named.self, Parent.self])
}
''')
        self.write("Bench.swift", "struct Bench: ParsableCommand {}\n")
        self.write("Named.swift", '''struct Named: ParsableCommand {
    // commandName: "comment-name", subcommands: [Orphan.self]
    static let configuration = CommandConfiguration(commandName: "explicit-name")
    let text = "commandName: string-name"
}
''')
        self.write("Parent.swift", '''struct Parent: ParsableCommand {
    static let configuration = CommandConfiguration(subcommands: [Child.self])
    struct Child: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "nested-name")
    }
}
struct Orphan: ParsableCommand {}
''')

    def write(self, name, text):
        (self.sources / name).write_text(text, encoding="utf-8")

    def commands(self):
        return audit.tool_commands(self.root, "uttrflow-dev")

    def test_only_registered_names_and_own_configuration_are_used(self):
        self.assertEqual(self.commands(), {"bench", "explicit-name", "parent"})

    def test_a_missing_root_is_refused(self):
        (self.sources / "Root.swift").unlink()
        with self.assertRaises(ValueError):
            self.commands()

    def test_an_ambiguous_root_is_refused(self):
        self.write("Other.swift", "@main\nstruct Other: ParsableCommand {}\n")
        with self.assertRaises(ValueError):
            self.commands()

    def test_a_missing_registered_declaration_is_refused(self):
        (self.sources / "Bench.swift").unlink()
        with self.assertRaises(ValueError):
            self.commands()

    def test_an_ambiguous_registered_declaration_is_refused(self):
        self.write("Other.swift", "struct Bench: ParsableCommand {}\n")
        with self.assertRaises(ValueError):
            self.commands()

    def test_a_nested_same_name_does_not_shadow_a_registered_module_type(self):
        self.write("Wrapper.swift", "struct Wrapper { struct Bench: ParsableCommand {} }\n")
        self.assertEqual(self.commands(), {"bench", "explicit-name", "parent"})

    def test_an_empty_configuration_keeps_the_registered_type_default(self):
        self.write("EmptyConfigName.swift", "struct EmptyConfigName: ParsableCommand { "
                   "static let configuration = CommandConfiguration() }\n")
        root = self.sources / "Root.swift"
        root.write_text(root.read_text().replace("Parent.self]", "Parent.self, EmptyConfigName.self]"))
        self.assertEqual(self.commands(), {"bench", "explicit-name", "parent", "empty-config-name"})

    def test_a_computed_registry_is_refused(self):
        self.write("Root.swift", "@main\nstruct Root: ParsableCommand { "
                   "static let configuration = CommandConfiguration(subcommands: makeCommands()) }\n")
        with self.assertRaises(ValueError):
            self.commands()

    def test_a_computed_registered_name_is_refused(self):
        self.write("Named.swift", "struct Named: ParsableCommand { "
                   "static let configuration = CommandConfiguration(commandName: chosenName) }\n")
        with self.assertRaises(ValueError):
            self.commands()

    def test_the_current_measurement_page_keeps_all_accepted_commands(self):
        self.assertEqual(audit.findings(audit.PACKAGE_ROOT, audit.PAGE), [])

    def test_a_documented_nested_name_is_refused(self):
        (self.root / "Docs").mkdir()
        (self.root / "Makefile").write_text("bench:\n")
        page = Path("Docs/page.md")
        (self.root / page).write_text("Run `uttrflow-dev nested-name`.\n")
        self.assertEqual(audit.findings(self.root, page),
                         ["uttrflow-dev nested-name: no such subcommand in Sources/uttrflow-dev"])

    def test_a_comment_or_string_root_is_not_registered(self):
        self.write("Decoys.swift", '''// @main struct CommentRoot: ParsableCommand {}
let text = "@main struct StringRoot: ParsableCommand {}"
''')
        self.assertEqual(self.commands(), {"bench", "explicit-name", "parent"})


if __name__ == "__main__":
    unittest.main()
