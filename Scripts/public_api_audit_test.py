#!/usr/bin/env python3
"""Checks the public API audit reads each declaration shape and finds exports nothing outside uses."""

import os
import tempfile
import unittest

import public_api_audit

CORE = """public import Foundation

@MainActor public final class Store {
    public private(set) var count = 0
    public init() {}
    public static func == (lhs: Store, rhs: Store) -> Bool { true }
    nonisolated public func lonely() {}
    func hidden() {}
}

public enum Shape { case round }
open class Base {}
"""

USER = "import Core\n\nlet store = Store()\n_ = store.count\n"
TESTABLE = "@testable import Core\n\nlet base = Base()\n"


class PublicApiTests(unittest.TestCase):
    def tree(self, files):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        for path, text in files.items():
            full = os.path.join(root.name, path)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w") as handle:
                handle.write(text)
        return root.name

    def test_reads_every_declaration_shape(self):
        root = self.tree({"Sources/Core/Store.swift": CORE})
        keys = [key for key, _ in public_api_audit.surface(os.path.join(root, "Sources"))]
        self.assertEqual(
            keys,
            ["Core class Store", "Core var count", "Core init init", "Core func ==", "Core func lonely",
             "Core enum Shape", "Core class Base"],
        )

    def test_unused_counts_only_outside_and_plain_import_uses(self):
        root = self.tree(
            {"Sources/Core/Store.swift": CORE, "Sources/App/Main.swift": USER, "Tests/CoreTests/T.swift": TESTABLE}
        )
        sources, tests = os.path.join(root, "Sources"), os.path.join(root, "Tests")
        found = public_api_audit.surface(sources)
        names = [key for key, _ in public_api_audit.unused(found, sources, tests)]
        self.assertEqual(names, ["Core func lonely", "Core enum Shape", "Core class Base"])

    def test_a_new_declaration_is_a_rise(self):
        before = public_api_audit.counts_of([("Core class Store", "a")])
        after = public_api_audit.counts_of([("Core class Store", "a"), ("Core func added", "b")])
        self.assertEqual(public_api_audit.ratchet.risen(after, before), {"Core func added": (0, 1)})
        self.assertEqual(public_api_audit.ratchet.risen(before, after), {})


if __name__ == "__main__":
    unittest.main()
