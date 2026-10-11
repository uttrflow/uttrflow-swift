"""Checks cache rules across same-module model extensions without an MLX import."""

from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

import perf_budget_audit as audit


class ModelExtensionCacheTests(unittest.TestCase):
    def failures(self, extension, module="SyntheticModel"):
        files = {
            "Sources/SyntheticModel/Model.swift": "import MLX\nactor SyntheticScorer {}",
            f"Sources/{module}/Lifecycle.swift": extension,
            "Sources/UttrflowLocalModel/GPUBufferCache.swift":
                "struct GPUBufferCache {\n    static let limit = 256 * 1_048_576\n}",
        }
        tree = SimpleNamespace(files={path: audit.blanked(text) for path, text in files.items()})
        findings = audit.Findings()
        audit.check_cache(tree, findings, [])
        return findings.failures

    def test_importless_model_release_requires_cache_clear(self):
        failures = self.failures("extension SyntheticScorer { func release() async { await weights.unload() } }")
        self.assertEqual(failures, [
            "cache: Sources/SyntheticModel/Lifecycle.swift:1 release() drops the model without clearing MLX's cache"
        ])

    def test_importless_model_pass_requires_cache_guard(self):
        failures = self.failures("extension SyntheticScorer { func answer() { container.perform { value() } } }")
        self.assertEqual(failures, [
            "cache: Sources/SyntheticModel/Lifecycle.swift:1 a model pass in answer() that neither caps MLX's cache nor clears it before or after it"
        ])

    def test_guarded_importless_model_extension_passes(self):
        extension = """extension SyntheticScorer {
    func release() async { bufferCachePasses.begin(); await weights.unload(); bufferCachePasses.end() }
    func answer() { beginPass(); defer { endPass() }; container.perform { value() } }
}"""
        self.assertEqual(self.failures(extension), [])

    def test_same_named_type_in_another_module_is_not_the_model(self):
        extension = "extension SyntheticScorer { func release() {} }"
        self.assertEqual(self.failures(extension, module="SyntheticOther"), [])


class ExtensionIntervalTests(unittest.TestCase):
    def resolved(self, module="SyntheticPipeline", owner="SyntheticFlow", duplicate=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {
                "Sources/SyntheticPipeline/Flow.swift":
                    "public import struct Foundation.Date\npublic import struct Foundation.UUID\n"
                    "actor SyntheticFlow { init(poll: Duration = .seconds(1)) {} }",
                f"Sources/{module}/Early.swift": f"extension {owner} {{ func step() {{}} }}",
            }
            if duplicate:
                files["Sources/SyntheticPipeline/Other.swift"] = (
                    "extension SyntheticFlow { init(poll: Duration = .seconds(2)) {} }")
            for path, text in files.items():
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text)
            return audit.seconds(audit.Tree(root), "poll", f"Sources/{module}/Early.swift")

    def test_extension_reads_its_type_default_interval(self):
        self.assertEqual(self.resolved(), 1.0)

    def test_other_module_cannot_supply_the_default_interval(self):
        self.assertIsNone(self.resolved(module="SyntheticOther"))

    def test_other_type_cannot_supply_the_default_interval(self):
        self.assertIsNone(self.resolved(owner="OtherFlow"))

    def test_ambiguous_default_intervals_remain_unresolved(self):
        self.assertIsNone(self.resolved(duplicate=True))


if __name__ == "__main__":
    unittest.main()
