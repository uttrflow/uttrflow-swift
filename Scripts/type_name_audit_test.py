#!/usr/bin/env python3
"""Checks the type-name audit finds a name declared in two modules and nothing else."""

import os
import tempfile
import unittest

import type_name_audit


class TypeNameTests(unittest.TestCase):
    def tree(self, files):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        for path, text in files.items():
            full = os.path.join(root.name, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(text)
        return root.name

    def counts(self, files):
        return type_name_audit.duplicates(self.tree(files))[0]

    def test_refuses_each_kind_of_declaration_in_two_modules(self):
        for kind in ("struct", "class", "enum", "protocol", "actor", "typealias"):
            with self.subTest(kind=kind):
                found = self.counts({"A/X.swift": f"public {kind} Shared {{}}\n", "B/Y.swift": f"{kind} Shared {{}}\n"})
                self.assertEqual(found, {"Shared": 1})

    def test_counts_every_module_past_the_first(self):
        files = {f"{module}/X.swift": "struct Shared {}\n" for module in ("A", "B", "C")}
        self.assertEqual(self.counts(files), {"Shared": 2})

    def test_reads_attributes_and_modifiers(self):
        files = {"A/X.swift": "@MainActor public final class Shared {}\n", "B/Y.swift": "indirect enum Shared {}\n"}
        self.assertEqual(self.counts(files), {"Shared": 1})

    def test_allows_one_name_twice_in_one_module(self):
        self.assertEqual(self.counts({"A/X.swift": "struct Shared {}\n", "A/Deep/Y.swift": "struct Shared {}\n"}), {})

    def test_ignores_nested_private_and_extension_declarations(self):
        files = {
            "A/X.swift": "struct Shared {}\n",
            "B/Y.swift": "struct Outer {\n    struct Shared {}\n}\nprivate struct Shared {}\nextension Shared {}\n",
        }
        self.assertEqual(self.counts(files), {})

    def test_ignores_a_typealias_that_reexports_the_same_type(self):
        files = {"A/X.swift": "public struct Shared {}\n", "B/Y.swift": "public typealias Shared = A.Shared\n"}
        self.assertEqual(self.counts(files), {})

    def test_refuses_a_typealias_to_a_different_type(self):
        files = {"A/X.swift": "public struct Shared {}\n", "B/Y.swift": "public typealias Shared = A.Other\n"}
        self.assertEqual(self.counts(files), {"Shared": 1})


if __name__ == "__main__":
    unittest.main()
