"""Checks cache rules across same-module model extensions without an MLX import."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

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


class SchedulerWakeupSiteTests(unittest.TestCase):
    expression = ".milliseconds(max(delay, 1))"
    scheduler = "Sources/Uttrflow/Suggestion/SuggestionTurnScheduling.swift"
    retired = "Sources/Uttrflow/Suggestion/SuggestionCoordinator.swift"

    def failures(self, path, expression=None):
        interval = expression or self.expression
        text = f"func wake() {{ Task {{ try? await sleep({interval}); wake(reason) }} }}"
        tree = SimpleNamespace(files={path: audit.blanked(text)}, constants={}, defaults={})
        findings = audit.Findings()
        registration = {key: value for key, value in audit.WAKEUPS_ALLOWED.items()
                        if key[1] == self.expression}
        with patch.dict(audit.WAKEUPS_ALLOWED, registration, clear=True), \
                patch.dict(audit.WAKEUPS_BOUND_BY, {}, clear=True):
            audit.check_wakeups(tree, findings, [])
        return findings.failures

    def test_extracted_scheduler_retains_its_exact_site_exception(self):
        self.assertEqual(self.failures(self.scheduler), [])

    def test_retired_coordinator_site_is_rejected(self):
        failures = self.failures(self.retired)
        self.assertTrue(any(self.retired in failure and "cannot resolve" in failure for failure in failures))
        self.assertTrue(any(self.scheduler in failure and "no longer has a site" in failure for failure in failures))

    def test_same_expression_in_another_file_is_rejected(self):
        unrelated = "Sources/Synthetic/Other.swift"
        self.assertTrue(any(unrelated in failure and "cannot resolve" in failure
                            for failure in self.failures(unrelated)))

    def test_changed_expression_at_the_scheduler_is_rejected(self):
        self.assertTrue(any(self.scheduler in failure and "cannot resolve" in failure
                            for failure in self.failures(self.scheduler, ".milliseconds(max(delay, 2))")))


class LatencySampleValidationTests(unittest.TestCase):
    root = Path(__file__).resolve().parent.parent

    def fixture(self, samples):
        corpus, lines = [], []

        def sample(stage, index):
            values = samples.get(stage, [])
            return values[index] if values else 0.0

        for category in audit.LATENCY_WAIT_CATEGORIES:
            for index in range(audit.LATENCY_MIN_SAMPLES):
                clip_id = f"synthetic-{category}-{index}"
                corpus.append({"id": clip_id, "category": category, "variant": "clean"})
                events = [{"kind": "asr", **{
                    field: str(sample(f"asr:{field}", index)) for field in audit.LATENCY_ASR_FIELDS}}]
                events += [{"kind": kind, "t0": "0", "t1": str(sample(kind, index))}
                           for kind in ("clean", "correct")]
                lines.append("BENCH " + json.dumps({
                    "event": "result", "id": clip_id, "mode": "rt", "cleaner": "shipping",
                    "wait": str(sample(f"wait:{category}", index)), "events": events}, allow_nan=False))
        return corpus, lines

    def run_cli(self, samples):
        corpus, lines = self.fixture(samples)
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            corpus_path, run_path = directory / "corpus.json", directory / "run.out"
            corpus_path.write_text(json.dumps(corpus))
            run_path.write_text("\n".join(lines) + "\n")
            return subprocess.run(
                [sys.executable, str(self.root / "Scripts/perf_budget_audit.py"),
                 "--root", str(self.root), "--latency", str(run_path), "--corpus", str(corpus_path)],
                text=True, capture_output=True, timeout=10)

    def test_cli_rejects_invalid_samples_in_each_budgeted_stage(self):
        targets = audit.latency_targets(audit.performance_doc(self.root))
        for stage in targets:
            for value in (float("nan"), float("inf"), float("-inf"), -1.0):
                with self.subTest(stage=stage, value=value):
                    result = self.run_cli({stage: [value] * audit.LATENCY_MIN_SAMPLES})
                    self.assertEqual(result.returncode, 1, result.stdout)
                    self.assertIn(stage, result.stderr)
                    self.assertIn("non-finite or negative duration", result.stderr)

    def test_cli_preserves_complete_zero_and_exact_budget_runs(self):
        targets = audit.latency_targets(audit.performance_doc(self.root))
        at_budget = {stage: [budget] * audit.LATENCY_MIN_SAMPLES for stage, (_, budget) in targets.items()}
        for samples in ({}, at_budget):
            with self.subTest(samples=samples):
                result = self.run_cli(samples)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = []
                for stage, (_, budget) in sorted(targets.items()):
                    count = 3 if stage.startswith("wait:") else 9
                    value = budget if samples else 0.0
                    expected.append(f"  ✓ {stage}: {count} samples, p95 {value:.3f}/{budget:.3f} s")
                self.assertEqual(result.stdout, "\n".join(expected) + "\n")

    def test_cli_preserves_slower_run_failures(self):
        targets = audit.latency_targets(audit.performance_doc(self.root))
        for stage, (_, budget) in targets.items():
            with self.subTest(stage=stage):
                result = self.run_cli({stage: [budget * 1.5] * audit.LATENCY_MIN_SAMPLES})
                self.assertEqual(result.returncode, 1)
                self.assertIn(stage, result.stderr)
                self.assertIn("p95", result.stderr)

    def test_cli_cannot_hide_one_invalid_sample_behind_good_samples(self):
        stage = f"wait:{audit.LATENCY_WAIT_CATEGORIES[0]}"
        result = self.run_cli({stage: [float("nan")] + [0.0] * (audit.LATENCY_MIN_SAMPLES - 1)})
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(stage, result.stderr)
        self.assertIn("non-finite or negative duration", result.stderr)

    def test_minimum_sample_precedence_and_unbudgeted_stages_are_preserved(self):
        stage, target = next(iter(audit.latency_targets(audit.performance_doc(self.root)).items()))
        short = {stage: [float("nan")] * (audit.LATENCY_MIN_SAMPLES - 1)}
        breaches, report = audit.latency_breaches({stage: target}, short)
        self.assertEqual(len(breaches), 1)
        self.assertIn(f"needs {audit.LATENCY_MIN_SAMPLES}", breaches[0])
        self.assertEqual(report, [])
        samples = {stage: [0.0] * audit.LATENCY_MIN_SAMPLES, "synthetic-unbudgeted": [float("nan")]}
        breaches, report = audit.latency_breaches({stage: target}, samples)
        self.assertEqual(breaches, [])
        self.assertEqual(len(report), 1)

    def test_existing_event_filters_ignore_ineligible_invalid_samples(self):
        corpus, lines = self.fixture({})
        for kind in ("fast", "rules", "failed", "unknown", "noise"):
            event = json.loads(lines[0][6:])
            event["wait"] = "nan"
            for step in event["events"]:
                for field in audit.LATENCY_ASR_FIELDS:
                    step[field] = "nan"
                step["t1"] = "nan"
            if kind == "fast":
                event["mode"] = "fast"
            elif kind == "rules":
                event["cleaner"] = "rules"
            elif kind == "failed":
                event["failed"] = "synthetic failure"
            else:
                event["id"] = kind
                if kind == "noise":
                    corpus.append({"id": kind, "category": "dur5", "variant": "noise"})
            lines.append("BENCH " + json.dumps(event))
        samples = audit.stage_samples(lines, {clip["id"]: clip for clip in corpus})
        targets = audit.latency_targets(audit.performance_doc(self.root))
        breaches, report = audit.latency_breaches(targets, samples)
        self.assertEqual(breaches, [])
        self.assertEqual(len(report), len(targets))


if __name__ == "__main__":
    unittest.main()
