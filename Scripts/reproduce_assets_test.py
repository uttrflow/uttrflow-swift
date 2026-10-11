#!/usr/bin/env python3
"""Proves reproduction matches a fixture tag and fails, naming the asset, on a changed seed or input digest."""

import json
import os
import subprocess
import tempfile
import unittest

import data_manifest
import reproduce_assets

FIT = (
    "import hashlib, os\n"
    "seeds = os.environ['RECIPE_SEEDS']\n"
    "table = open('table.txt', 'rb').read()\n"
    "weights = hashlib.sha256(table + seeds.encode()).hexdigest()\n"
    "os.makedirs(os.path.dirname(os.environ['RECIPE_OUTPUT']), exist_ok=True)\n"
    "open(os.environ['RECIPE_OUTPUT'], 'w').write(weights)\n"
)
ASSET = "Sources/Module/Resources/weights.txt"


def run(root, *args):
    subprocess.run(["git", "-C", root, *args], check=True, capture_output=True)


class ReproduceAssetsTests(unittest.TestCase):
    def repo(self, mutate=None):
        root = tempfile.mkdtemp()
        run(root, "init", "-q")
        run(root, "config", "user.email", "dev@example.test")
        run(root, "config", "user.name", "dev")
        with open(os.path.join(root, "fit.py"), "w") as handle:
            handle.write(FIT)
        with open(os.path.join(root, "table.txt"), "w") as handle:
            handle.write("feature table")
        run(root, "add", "fit.py", "table.txt")
        run(root, "commit", "-q", "-m", "fit tool")
        revision = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        recipe = {
            "fitToolRevision": revision, "featureSpecVersion": "1", "seeds": [7], "engine": "fixture-1",
            "inputs": [{"name": "table", "where": "tree", "path": "table.txt",
                        "sha256": reproduce_assets.file_digest(os.path.join(root, "table.txt"))}],
            "command": ["python3", "fit.py"],
        }
        out = subprocess.run(["python3", "fit.py"], cwd=root, capture_output=True, text=True,
                             env=dict(os.environ, RECIPE_SEEDS="7", RECIPE_OUTPUT=ASSET))
        self.assertEqual(out.returncode, 0, out.stderr)
        entry = {"path": ASSET, "origin": "generated", "licence": "MIT", "redistribution": True,
                 "sha256": reproduce_assets.file_digest(os.path.join(root, ASSET)),
                 "bytes": os.path.getsize(os.path.join(root, ASSET)), "recipe": recipe}
        if mutate:
            mutate(entry)
        os.makedirs(os.path.join(root, "Resources"))
        with open(os.path.join(root, data_manifest.MANIFEST), "w") as handle:
            json.dump({"schema": 1, "assets": [entry]}, handle)
        run(root, "add", "Resources", "Sources")
        run(root, "commit", "-q", "-m", "release")
        run(root, "tag", "v1")
        return root

    def test_matches_on_a_fixture_tag(self):
        lines, failed = reproduce_assets.reproduce(self.repo(), "v1", None)
        self.assertFalse(failed, lines)
        self.assertIn("ok   " + ASSET, lines)

    def test_changed_seed_fails_naming_the_asset(self):
        lines, failed = reproduce_assets.reproduce(self.repo(lambda e: e["recipe"].update(seeds=[8])), "v1", None)
        self.assertTrue(failed)
        self.assertIn("FAIL " + ASSET, lines)

    def test_changed_input_digest_fails_naming_the_asset(self):
        lines, failed = reproduce_assets.reproduce(
            self.repo(lambda e: e["recipe"]["inputs"][0].update(sha256="0" * 64)), "v1", None)
        self.assertTrue(failed)
        self.assertIn("FAIL " + ASSET, lines)

    def test_cache_input_needs_the_cache(self):
        def mutate(entry):
            entry["recipe"]["inputs"][0]["where"] = "cache"
        lines, failed = reproduce_assets.reproduce(self.repo(mutate), "v1", None)
        self.assertTrue(failed)
        self.assertTrue(any("no --cache" in line for line in lines))

    def test_unknown_tag_fails(self):
        _, failed = reproduce_assets.reproduce(self.repo(), "v9", None)
        self.assertTrue(failed)

    def test_manifest_check_refuses_a_partial_recipe(self):
        self.assertEqual(data_manifest.recipe_problems({}), [])
        self.assertIn("recipe missing seeds", data_manifest.recipe_problems({"recipe": {}}))


if __name__ == "__main__":
    unittest.main()
