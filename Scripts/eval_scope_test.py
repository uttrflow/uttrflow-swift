"""Prove that the required evaluation job runs for each quality-grid input."""

from pathlib import Path
import re
import unittest

WORKFLOW = Path(__file__).resolve().parent.parent / ".github/workflows/eval.yml"


class EvalScopeTests(unittest.TestCase):
    def setUp(self):
        source = WORKFLOW.read_text()
        expression = re.search(r"read_by_the_lane='([^']+)'", source)
        self.assertIsNotNone(expression)
        self.scope = re.compile(expression.group(1))

    def test_quality_grid_sources_and_tests_require_evaluation(self):
        paths = [
            "Sources/UttrflowClipboard/ClipKindDetector.swift",
            "Sources/UttrflowTestSupport/QualityGridReport.swift",
            "Tests/UttrflowCoreTests/VoiceActivityOnsetGridTests.swift",
            "Tests/UttrflowCoreTests/VoiceActivityConditionTests.swift",
            "Tests/UttrflowAITests/Passes/NumberRoundTripTests.swift",
            "Tests/UttrflowAITests/InflectedDictionaryFormsTests.swift",
            "Tests/UttrflowDictionaryTests/LexiconNeighboursTests.swift",
            "Tests/UttrflowClipboardTests/ClipKindOracleTests.swift",
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertIsNotNone(self.scope.search(path))

    def test_quality_grid_tooling_requires_evaluation(self):
        for path in [
            "Scripts/quality_grid_scorecard.py", "Scripts/quality_grid_scorecard_test.py",
            "Scripts/quality_grid_baseline.json", "Scripts/eval_scope_test.py",
        ]:
            with self.subTest(path=path):
                self.assertIsNotNone(self.scope.search(path))

    def test_existing_corpus_inputs_still_require_evaluation(self):
        for module in ["AI", "Core", "Dictionary", "Eval", "Pipeline", "Speech"]:
            with self.subTest(module=module):
                self.assertIsNotNone(self.scope.search(f"Sources/Uttrflow{module}/Input.swift"))
        for path in [
            "Tests/UttrflowEvalTests/CorpusTests.swift", "Scripts/rules_scorecard.py",
            "Scripts/rules_scorecard.json", "Scripts/scorecard_accepted.txt",
            "Scripts/seam_baseline.json", "Makefile", "Package.swift", "Package.resolved",
            ".github/workflows/eval.yml",
        ]:
            with self.subTest(path=path):
                self.assertIsNotNone(self.scope.search(path))

    def test_unrelated_documentation_still_skips_swift_work(self):
        for path in ["Docs/clipboard-store.md", "README.md", "CONTRIBUTING.md"]:
            with self.subTest(path=path):
                self.assertIsNone(self.scope.search(path))


if __name__ == "__main__":
    unittest.main()
