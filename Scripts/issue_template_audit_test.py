#!/usr/bin/env python3
"""Proves the issue template audit catches every prompt that would publish forbidden content."""

import os
import plistlib
import re
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIT = os.path.join(HERE, "issue_template_audit.py")


def run(audit_args, working=None):
    return subprocess.run(
        [sys.executable, AUDIT, *audit_args], cwd=working, capture_output=True, text=True
    )


class SelfTest(unittest.TestCase):
    """The audit's own fixtures prove its reasoning; they have to keep passing."""

    def test_self_test_passes(self):
        run = subprocess.run([sys.executable, AUDIT, "--self-test"], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("self-test passed", run.stdout)


class TreeTest(unittest.TestCase):
    """The repository's own templates must stay clean; a regression here means the bug returns."""

    REPO = os.path.dirname(HERE)

    def test_tree_passes(self):
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.REPO, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("none invite content", run.stdout)

    def test_bug_report_version_placeholder_uses_current_format(self):
        with open(
            os.path.join(self.REPO, ".github", "ISSUE_TEMPLATE", "bug_report.yml"),
            encoding="utf-8",
        ) as handle:
            template = handle.read()
        plist_path = os.path.join(self.REPO, "Resources", "Uttrflow-Info.plist")
        with open(plist_path, "rb") as handle:
            app_version = plistlib.load(handle)["CFBundleShortVersionString"]
        version = re.search(
            r'id: version\s+attributes:\s+label: Uttrflow version\s+'
            r'description:[^\n]+\s+placeholder: "([^"]+)"',
            template,
        )
        macos = re.search(
            r'id: macos\s+attributes:\s+label: macOS version\s+'
            r'placeholder: "([^"]+)"',
            template,
        )
        self.assertIsNotNone(version)
        self.assertEqual(version.group(1), app_version)
        self.assertIsNotNone(macos)
        self.assertRegex(macos.group(1), r"^26\.\d+\.\d+$")


class DictationErrorTemplateTest(unittest.TestCase):
    """The wrong-dictation form offers exactly the taxonomy's classes and demands redaction."""

    REPO = os.path.dirname(HERE)

    def read(self, *parts):
        with open(os.path.join(self.REPO, *parts), encoding="utf-8") as handle:
            return handle.read()

    def test_error_classes_equal_taxonomy(self):
        template = self.read(".github", "ISSUE_TEMPLATE", "dictation_error.yml")
        doc = self.read("Docs", "accuracy-targets.md")
        section = doc.split("## The error taxonomy", 1)[1].split("\n## ", 1)[0]
        taxonomy = re.findall(r"^\| \*\*([^*]+)\*\* \|", section, re.MULTILINE)
        block = re.search(r"id: error-class\n(?:.*\n)*?\s+options:\n((?:\s+- .*\n)+)", template)
        self.assertIsNotNone(block)
        options = re.findall(r"^\s+- (.+)$", block.group(1), re.MULTILINE)
        self.assertEqual(len(taxonomy), 3)
        self.assertEqual(options, taxonomy)

    def test_redaction_is_required_before_any_text(self):
        template = self.read(".github", "ISSUE_TEMPLATE", "dictation_error.yml")
        note = "Replace names, numbers and addresses with invented ones; do not paste real messages."
        self.assertRegex(template, re.escape(note) + r"\n\s+required: true")
        self.assertLess(template.index(note), template.index("type: textarea"))
        self.assertNotRegex(template, r"(?i)paste (?:the|your) (?:transcript|message)")


class ReasonTest(unittest.TestCase):
    """An invented bad template must be caught; the test runs the audit against a throwaway tree."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uttrflow-template-test-")
        os.makedirs(os.path.join(self.tmp, ".github", "ISSUE_TEMPLATE"))
        self.addCleanup(self._cleanup)

    def _cleanup(self):
        import shutil

        shutil.rmtree(self.tmp, ignore_errors=True)

    def _write(self, name, text):
        path = os.path.join(self.tmp, ".github", "ISSUE_TEMPLATE", name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def test_inviting_phrase_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: alternatives\n"
            "    attributes:\n"
            "      label: What you do instead today\n"
            "      description: Including other apps.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("invites product names", run.stderr)

    def test_workflow_field_without_warning_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: alternatives\n"
            "    attributes:\n"
            "      label: What you do instead today\n"
            "      description: A capability you reach for.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("no publication warning", run.stderr)

    def test_passing_template_is_accepted(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: markdown\n"
            "    attributes:\n"
            "      value: |\n"
            "        **Publication note.** What you write here is published.\n"
            "  - type: textarea\n"
            "    id: alternatives\n"
            "    attributes:\n"
            "      label: What you do today\n"
            "      description: The capability or workflow you reach for.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertIn("none invite content", run.stdout)

    def test_quote_about_another_product_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: notes\n"
            "    attributes:\n"
            "      label: Notes\n"
            "      description: Quote from the other product so we can compare.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("identifying detail of another product", run.stderr)

    def test_screenshot_of_another_product_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: evidence\n"
            "    attributes:\n"
            "      label: Evidence\n"
            "      description: Attach a screenshot from the other tool.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("identifying detail of another product", run.stderr)

    def test_link_to_another_product_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: references\n"
            "    attributes:\n"
            "      label: References\n"
            "      description: Share a link to the other app's docs.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("identifying detail of another product", run.stderr)

    def test_pricing_of_another_product_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: budget\n"
            "    attributes:\n"
            "      label: Budget\n"
            "      description: The price of the other product.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("identifying detail of another product", run.stderr)

    def test_identifying_description_of_another_product_is_refused(self):
        self._write(
            "feature_request.yml",
            "name: feature\nbody:\n"
            "  - type: textarea\n"
            "    id: context\n"
            "    attributes:\n"
            "      label: Context\n"
            "      description: Describe the features of the other tool.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 1, run.stdout)
        self.assertIn("identifying detail of another product", run.stderr)

    def test_bug_report_does_not_trip_on_own_evidence(self):
        self._write(
            "bug_report.yml",
            "name: bug\nbody:\n"
            "  - type: textarea\n"
            "    id: repro\n"
            "    attributes:\n"
            "      label: Steps\n"
            "      description: Paste the error message and a screenshot of the problem.\n",
        )
        run = subprocess.run(
            [sys.executable, AUDIT], cwd=self.tmp, capture_output=True, text=True
        )
        self.assertEqual(run.returncode, 0, run.stdout)
        self.assertIn("none invite content", run.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=1)
