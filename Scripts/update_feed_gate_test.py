#!/usr/bin/env python3
"""Tests the update feed gate used by bundle.sh and publish.sh."""

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import json


HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "update_feed_gate.py")
APPCAST = os.path.join(HERE, "appcast.py")
CASES = os.path.join(HERE, "update_feed_cases.json")
KEY = "apWgly8fYgdo1U2MUj56SuqUqZ4QHv5GRZIbuLT0PGE="


class FeedGateTests(unittest.TestCase):
    def run_gate(self, *arguments):
        return subprocess.run(
            [sys.executable, GATE, *arguments],
            capture_output=True,
            text=True,
        )

    def write_plist(self, **values):
        handle = tempfile.NamedTemporaryFile(prefix="uttrflow-feed-", suffix=".plist", delete=False)
        self.addCleanup(lambda: os.path.exists(handle.name) and os.unlink(handle.name))
        with handle:
            plistlib.dump(values, handle)
        return handle.name

    def test_classifies_https_and_loopback_feeds(self):
        cases = {
            "https://example.com/a.xml": "https",
            "http://127.0.0.1:8080/a.xml": "local",
            "http://localhost/a.xml": "local",
            "http://[::1]/a.xml": "local",
        }
        for url, expected in cases.items():
            with self.subTest(url=url):
                run = self.run_gate("classify", url)
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertEqual(run.stdout.strip(), expected)

    def test_agrees_with_the_table_the_app_is_tested_against(self):
        with open(CASES, encoding="utf-8") as handle:
            cases = json.load(handle)
        for url in cases["accepted"]:
            with self.subTest(url=url):
                self.assertEqual(self.run_gate("classify", url).returncode, 0)
        for url in cases["refused"]:
            with self.subTest(url=url):
                self.assertNotEqual(self.run_gate("classify", url).returncode, 0)

    def test_refuses_lookalikes_and_malformed_feeds(self):
        for url in [
            "http://127.0.0.1.example.com/a.xml",
            "http://localhost.example.com/a.xml",
            "https:///a.xml",
            "http://[::1.example.com]/a.xml",
        ]:
            with self.subTest(url=url):
                self.assertEqual(self.run_gate("classify", url).returncode, 1)

    def test_refuses_placeholder_keys(self):
        for key in [
            "",
            "not a key",
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            KEY[:-8] + "=",
            KEY + "AAAA",
            "YOUR_PUBLIC_KEY_HERE",
        ]:
            with self.subTest(key=key):
                self.assertEqual(self.run_gate("check-key", key).returncode, 1)
                plist = self.write_plist(
                    SUFeedURL="https://example.com/appcast.xml",
                    SUPublicEDKey=key,
                    SUVerifyUpdateBeforeExtraction=True,
                )
                self.assertEqual(self.run_gate("check-plist", plist).returncode, 1)
        self.assertEqual(self.run_gate("check-key", KEY).returncode, 0)

    def test_local_feeds_are_allowed_for_rehearsal_but_not_publication(self):
        plist = self.write_plist(
            SUFeedURL="http://[::1]/appcast.xml",
            SUPublicEDKey=KEY,
            SUVerifyUpdateBeforeExtraction=True,
        )
        run = self.run_gate("check-plist", plist)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.strip(), "local")

        run = self.run_gate("check-plist", plist, "--forbid-local")
        self.assertEqual(run.returncode, 1)
        self.assertIn("loopback", run.stderr)

    def test_publishable_plist_needs_key_and_pre_extraction_verification(self):
        good = self.write_plist(
            SUFeedURL="https://api.uttrflow.com/v1/updates/macos/appcast.xml",
            SUPublicEDKey=KEY,
            SUVerifyUpdateBeforeExtraction=True,
        )
        self.assertEqual(self.run_gate("check-plist", good, "--forbid-local").returncode, 0)

        no_key = self.write_plist(
            SUFeedURL="https://api.uttrflow.com/v1/updates/macos/appcast.xml",
            SUVerifyUpdateBeforeExtraction=True,
        )
        self.assertEqual(self.run_gate("check-plist", no_key).returncode, 1)

        verifies_late = self.write_plist(
            SUFeedURL="https://api.uttrflow.com/v1/updates/macos/appcast.xml",
            SUPublicEDKey=KEY,
            SUVerifyUpdateBeforeExtraction=False,
        )
        self.assertEqual(self.run_gate("check-plist", verifies_late).returncode, 1)

    def write_appcast(self, version, build):
        directory = tempfile.mkdtemp(prefix="uttrflow-appcast-")
        self.addCleanup(lambda: shutil.rmtree(directory, ignore_errors=True))
        path = os.path.join(directory, "appcast.xml")
        environment = dict(
            os.environ,
            VERSION=version,
            BUILD=build,
            ARCHIVE_NAME="Uttrflow.zip",
            ARCHIVE_SIZE="1024",
            SIGNATURE='sparkle:edSignature="c2lnbmF0dXJl" length="1024"',
            REPO="example/releases",
            NOTES_URL="https://example.com/notes",
            TAG=f"v{version}",
            MINIMUM_SYSTEM="26.0",
        )
        run = subprocess.run([sys.executable, APPCAST, path], capture_output=True, text=True, env=environment)
        self.assertEqual(run.returncode, 0, run.stderr)
        return path

    def test_patch_revision_sorts_above_the_broken_release(self):
        broken = self.write_appcast("26.0926.0", "9")
        patch = self.write_appcast("26.0926.1", "10")
        run = self.run_gate("check-order", broken, patch)
        self.assertEqual(run.returncode, 0, run.stderr)

        for version, build in [("26.0926.1", "9"), ("26.0926.0", "10"), ("26.0925.3", "10")]:
            with self.subTest(version=version, build=build):
                stale = self.write_appcast(version, build)
                self.assertEqual(self.run_gate("check-order", broken, stale).returncode, 1)

    def test_order_check_refuses_a_prerelease_as_the_patch(self):
        broken = self.write_appcast("26.0926.0", "9")
        candidate = self.write_appcast("26.0926.1-rc.1", "10")
        self.assertEqual(self.run_gate("check-order", broken, candidate).returncode, 1)


if __name__ == "__main__":
    unittest.main(verbosity=1)
