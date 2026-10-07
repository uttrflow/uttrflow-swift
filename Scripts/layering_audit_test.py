#!/usr/bin/env python3
"""Checks the layering audit refuses each way a logic module can reach the platform."""

import os
import tempfile
import unittest

import layering_audit

MANIFEST = """
let package = Package(
    targets: [
        .target(name: "UttrflowCore"),
        .target(
            name: "UttrflowAI",
            dependencies: ["UttrflowCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/UttrflowAI"
        ),
        .target(name: "UttrflowInput", dependencies: ["UttrflowCore", "UttrflowAppKitFree"]),
        .executableTarget(name: "Uttrflow", dependencies: ["UttrflowInput"]),
        .testTarget(name: "UttrflowAITests", dependencies: ["UttrflowInput"]),
    ]
)
"""


class LayeringTests(unittest.TestCase):
    def tree(self, files):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        for path, text in files.items():
            full = os.path.join(root.name, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(text)
        return root.name

    def imports(self, files):
        return [text for _, text in layering_audit.import_violations(self.tree(files))]

    def test_refuses_each_ui_framework_in_a_logic_module(self):
        for framework in layering_audit.UI_FRAMEWORKS:
            with self.subTest(framework=framework):
                found = self.imports({"Logic/A.swift": f"import {framework}\n"})
                self.assertEqual(len(found), 1)

    def test_refuses_qualified_and_attributed_imports(self):
        source = "@preconcurrency import SwiftUI\n  public import AppKit\nimport struct AppKit.NSRect\n"
        self.assertEqual(len(self.imports({"Logic/A.swift": source})), 3)

    def test_refuses_an_import_in_a_nested_directory(self):
        self.assertEqual(len(self.imports({"Logic/Deep/Er/A.swift": "import Cocoa\n"})), 1)

    def test_allows_platform_modules_to_import_ui_frameworks(self):
        for module in layering_audit.PLATFORM_MODULES:
            with self.subTest(module=module):
                self.assertEqual(self.imports({f"{module}/A.swift": "import AppKit\n"}), [])

    def test_ignores_foundation_comments_and_lookalike_names(self):
        source = "import Foundation\n// import AppKit\nimport AppKitFree\nlet note = \"import SwiftUI\"\n"
        self.assertEqual(self.imports({"Logic/A.swift": source}), [])

    def test_refuses_a_logic_target_that_depends_on_a_platform_module(self):
        manifest = '.target(name: "UttrflowAI", dependencies: ["UttrflowCore", "UttrflowClipboard"])'
        self.assertEqual(len(layering_audit.dependency_violations(manifest)), 1)

    def test_refuses_a_dependency_named_with_target_syntax(self):
        manifest = '.executableTarget(name: "uttrflow-bakeoff", dependencies: [.target(name: "UttrflowInput")])'
        self.assertEqual(len(layering_audit.dependency_violations(manifest)), 1)

    def test_allows_platform_to_platform_and_platform_to_logic(self):
        manifest = '.target(name: "UttrflowInput", dependencies: ["UttrflowCore", "UttrflowPermissions"])'
        self.assertEqual(layering_audit.dependency_violations(manifest), [])

    def test_ignores_test_targets_and_products(self):
        self.assertEqual(layering_audit.dependency_violations(MANIFEST), [])

    def test_reads_every_target_in_the_manifest(self):
        names = [name for name, _ in layering_audit.targets_in(MANIFEST)]
        self.assertEqual(names, ["UttrflowCore", "UttrflowAI", "UttrflowInput", "Uttrflow"])

    def test_refuses_an_import_edge_the_allowed_list_does_not_name(self):
        manifest = '.target(name: "UttrflowAI", dependencies: ["UttrflowCore"])\n.target(name: "UttrflowSpeech")'
        root = self.tree({"UttrflowAI/A.swift": "import Foundation\nimport UttrflowSpeech\n"})
        edges = layering_audit.module_edges(manifest, root)
        unknown, stale = layering_audit.edge_violations(edges, {"UttrflowAI": ["UttrflowCore"]})
        self.assertEqual(unknown, [f"{os.path.join(root, 'UttrflowAI', 'A.swift')}:2: UttrflowAI -> UttrflowSpeech"])
        self.assertEqual(stale, [])

    def test_refuses_a_manifest_edge_the_allowed_list_does_not_name(self):
        edges = layering_audit.module_edges('.target(name: "UttrflowAI", dependencies: ["UttrflowSpeech"])', self.tree({}))
        unknown, _ = layering_audit.edge_violations(edges, {"UttrflowAI": []})
        self.assertEqual(unknown, ["Package.swift: UttrflowAI -> UttrflowSpeech"])

    def test_refuses_an_allowed_edge_nothing_uses_and_a_reason_for_no_edge(self):
        _, stale = layering_audit.edge_violations([], {"UttrflowAI": ["UttrflowCore"]}, {"UttrflowAI -> UttrflowSpeech": "x"})
        self.assertEqual(len(stale), 2)

    def test_allows_every_edge_on_main(self):
        with open(layering_audit.MANIFEST) as handle:
            self.assertEqual(layering_audit.check_edges(handle.read()), 0)


if __name__ == "__main__":
    unittest.main()
