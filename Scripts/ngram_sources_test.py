#!/usr/bin/env python3
"""Proves the n-gram source check refuses an unlisted, changed or wrongly licensed source."""

import io
import os
import tempfile
import unittest

import ngram_sources


class NgramSourcesTests(unittest.TestCase):
    def cache(self, parent=None):
        folder = tempfile.mkdtemp(dir=parent)
        archive = os.path.join(folder, "docs.tar.gz")
        with open(archive, "wb") as handle:
            handle.write(b"text")
        entry = {
            "name": "docs",
            "publisher": "Example Project",
            "url": "https://example.com/docs.tar.gz",
            "revision": "v1.0.0",
            "licence": "MIT",
            "archive": "docs.tar.gz",
            "sha256": ngram_sources.digest(archive),
            "fetched": "2000-01-01",
        }
        return folder, archive, entry

    def test_listed_matching_cache_passes(self):
        folder, _, entry = self.cache()
        self.assertEqual(ngram_sources.check_entries([entry]), [])
        self.assertEqual(ngram_sources.check_cache([entry], folder), [])

    def test_share_alike_licence_fails(self):
        _, _, entry = self.cache()
        entry["licence"] = "CC-BY-SA-4.0"
        self.assertIn("not in the allowlist", ngram_sources.check_entries([entry])[0])

    def test_missing_field_fails(self):
        _, _, entry = self.cache()
        del entry["revision"]
        self.assertIn("missing revision", ngram_sources.check_entries([entry])[0])

    def test_unlisted_archive_fails(self):
        folder, _, entry = self.cache()
        with open(os.path.join(folder, "forum.txt"), "wb") as handle:
            handle.write(b"post")
        self.assertIn("not in", ngram_sources.check_cache([entry], folder)[0])

    def test_changed_archive_fails(self):
        folder, archive, entry = self.cache()
        with open(archive, "wb") as handle:
            handle.write(b"edit")
        self.assertIn("SHA-256 differs", ngram_sources.check_cache([entry], folder)[0])

    def test_cache_under_application_support_is_refused(self):
        base = tempfile.mkdtemp()
        user = os.path.join(base, "Library", "Application Support")
        os.makedirs(user)
        folder, _, entry = self.cache(parent=user)
        self.assertIn("never reads user data", ngram_sources.check_cache([entry], folder)[0])

    def test_fetch_keeps_a_matching_download_and_refuses_a_changed_one(self):
        folder, archive, entry = self.cache()
        os.remove(archive)
        served = io.BytesIO(b"text")
        self.assertEqual(ngram_sources.fetch([entry], folder, opener=lambda _: served), [])
        self.assertEqual(ngram_sources.check_cache([entry], folder), [])
        os.remove(archive)
        changed = io.BytesIO(b"edit")
        failures = ngram_sources.fetch([entry], folder, opener=lambda _: changed)
        self.assertIn("differs", failures[0])
        self.assertEqual(os.listdir(folder), [])

    def test_shipped_manifest_is_valid(self):
        self.assertEqual(ngram_sources.check_entries(ngram_sources.load(ngram_sources.ROOT)), [])


if __name__ == "__main__":
    unittest.main()
