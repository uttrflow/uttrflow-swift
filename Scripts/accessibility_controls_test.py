#!/usr/bin/env python3
"""Checks the accessibility table finds each control, reads its name source and refuses stale rows."""

import os
import tempfile
import unittest

import accessibility_controls as table

DOC = "# Controls\n\n<!-- accessibility-controls:begin -->\n<!-- accessibility-controls:end -->\n"


class AccessibilityControlsTests(unittest.TestCase):
    def tree(self, files, doc=DOC, status=None):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        files = {**files, table.DOC: doc}
        if status is not None:
            files[table.STATUS] = status
        for path, text in files.items():
            full = os.path.join(root.name, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(text)
        return root.name

    def names(self, source):
        root = self.tree({"Sources/Uttrflow/Panel/A.swift": source})
        return [row["name"] for row in table.controls(root)]

    def test_reads_each_name_source(self):
        source = (
            'Button("Copy") { copy() }\n'
            "Button(title) { go() }\n"
            "Button(action: go) { Image(systemName: \"x\") }\n"
            "Button(action: go) { Image(systemName: \"x\") }\n    .accessibilityLabel(\"Close\")\n"
            "Button { go() } label: { Text(title) }\n"
            'TextField("", text: $query)\n'
        )
        self.assertEqual(
            self.names(source),
            ['text "Copy"', "expression", "none found", "accessibilityLabel", "label view", "none found"],
        )

    def test_a_field_inside_a_naming_container_reads_the_container_label(self):
        source = (
            "PageEditorField(\n    label: editor.wordLabel, symbolName: \"x\", tint: tint\n) {\n"
            '    TextField("", text: word)\n}\n'
            'VStack {\n    TextField("", text: other)\n}\n'
        )
        self.assertEqual(self.names(source), ["container label", "none found"])

    def test_reads_the_whole_constructor_and_its_modifiers_across_lines(self):
        source = (
            'TextField(\n    "Line \\(index + 1)",\n    text: line\n)\n'
            "TextField(\n    sheet.placeholder,\n    text: draft\n)\n"
            "Menu {\n" + "    Button(item) { run() }\n" * 14 + "} label: {\n    Image(systemName: \"x\")\n}\n"
            + "    .fixedSize()\n" * 12 + '    .accessibilityLabel("More")\n'
            "Button(action: open) {\n    VStack {\n        Text(title)\n    }\n}\n"
        )
        self.assertEqual(
            [name for name in self.names(source) if name != "expression"],
            ['text "Line \\(index + 1)"', "accessibilityLabel", "label view"],
        )

    def test_a_hidden_control_and_an_appkit_control_labelled_later_are_not_unnamed(self):
        source = (
            'Button("", action: cancel)\n    .opacity(0)\n    .accessibilityHidden(true)\n'
            "func make() {\n    let list = NSPopUpButton(frame: .zero)\n    alert.messageText = title\n"
            "    list.setAccessibilityLabel(alert.messageText)\n}\n"
            "func other() {\n    let menu = NSPopUpButton(frame: .zero)\n}\n"
        )
        self.assertEqual(self.names(source), ["hidden from accessibility", "accessibilityLabel", "none found"])

    def test_a_return_type_is_not_a_control(self):
        self.assertEqual(self.names('func item() -> NSMenuItem {\n    NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")\n}\n'),
                         ['text "Quit"'])

    def test_check_refuses_a_control_with_no_accessible_name(self):
        root = self.tree({"Sources/Uttrflow/Dock/A.swift": 'Toggle("", isOn: $on)\n'})
        table.main([], root)
        self.assertEqual(table.main(["--check"], root), 1)

    def test_ignores_comments_and_lookalike_names(self):
        self.assertEqual(self.names('// Button("x")\nlet b = MyButton(x)\nfoo.Button(y)\n'), [])

    def test_screen_comes_from_the_directory(self):
        root = self.tree({"Sources/Uttrflow/Dock/A.swift": 'Button("x") {}\n'})
        self.assertEqual(table.controls(root)[0]["screen"], "Dock")

    def test_check_refuses_a_stale_table_then_passes_once_written(self):
        root = self.tree({"Sources/Uttrflow/Dock/A.swift": 'Button("x") {}\n'})
        self.assertEqual(table.main(["--check"], root), 1)
        self.assertEqual(table.main([], root), 0)
        self.assertEqual(table.main(["--check"], root), 0)

    def test_refuses_a_status_for_a_missing_control_or_a_bad_value(self):
        status = '{"Sources/Uttrflow/Dock/A.swift#Button#1": "ok", "gone#Button#1": "pass"}'
        root = self.tree({"Sources/Uttrflow/Dock/A.swift": 'Button("x") {}\n'}, status=status)
        self.assertEqual(len(table.problems(table.controls(root), table.load_status(root))), 2)

    def test_records_a_walked_status_in_the_table(self):
        status = '{"Sources/Uttrflow/Dock/A.swift#Button#1": "#2445"}'
        root = self.tree({"Sources/Uttrflow/Dock/A.swift": 'Button("x") {}\n'}, status=status)
        table.main([], root)
        with open(os.path.join(root, table.DOC)) as handle:
            self.assertIn("| #2445 |", handle.read())


if __name__ == "__main__":
    unittest.main()
