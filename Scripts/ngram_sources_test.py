#!/usr/bin/env python3
"""Proves the n-gram source check refuses an unlisted, changed or wrongly licensed source."""

import io
import os
import tarfile
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
            "kind": "text",
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

    def lexicon(self, notice=b"Copyright notice"):
        folder = tempfile.mkdtemp()
        root = tempfile.mkdtemp()
        with open(os.path.join(root, "NOTICE.txt"), "wb") as handle:
            handle.write(b"Copyright notice")
        archive = os.path.join(folder, "lexicon.tar.gz")
        with tarfile.open(archive, "w:gz") as tar:
            info = tarfile.TarInfo("lexicon/LICENSE")
            info.size = len(notice)
            tar.addfile(info, io.BytesIO(notice))
        entry = {
            "name": "lexicon",
            "kind": "lexicon",
            "publisher": "Example University",
            "url": "https://example.com/lexicon.tar.gz",
            "revision": "abc123",
            "licence": "BSD-2-Clause",
            "archive": "lexicon.tar.gz",
            "sha256": ngram_sources.digest(archive),
            "fetched": "2000-01-01",
            "notice": "NOTICE.txt",
            "noticeInArchive": "lexicon/LICENSE",
        }
        return folder, root, entry

    def test_lexicon_with_matching_notice_passes(self):
        folder, root, entry = self.lexicon()
        self.assertEqual(ngram_sources.check_entries([entry], root), [])
        self.assertEqual(ngram_sources.check_cache([entry], folder, root), [])

    def test_lexicon_without_notice_fails(self):
        _, root, entry = self.lexicon()
        del entry["notice"]
        self.assertIn("needs notice", ngram_sources.check_entries([entry], root)[0])

    def test_lexicon_whose_licence_changed_fails(self):
        folder, root, entry = self.lexicon(notice=b"Different terms")
        self.assertIn("licence text differs", ngram_sources.check_cache([entry], folder, root)[0])

    def test_unknown_kind_fails(self):
        _, _, entry = self.cache()
        entry["kind"] = "corpus"
        self.assertIn("kind must be", ngram_sources.check_entries([entry])[0])

    def test_shipped_manifest_is_valid(self):
        self.assertEqual(ngram_sources.check_entries(ngram_sources.load(ngram_sources.ROOT)), [])


if __name__ == "__main__":
    unittest.main()
