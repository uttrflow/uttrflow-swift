#!/usr/bin/env python3
"""Proves app packaging ignores cached products outside the app build graph."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import bundle_products

ROOT = Path(__file__).resolve().parent.parent


class BundleProductsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.derived = Path(self.temporary.name).resolve()
        self.products = self.derived / "Build/Products/Release"
        self.products.mkdir(parents=True)
        self.description = self.derived / "Build/Intermediates.noindex/XCBuildData/app.xcbuilddata"
        self.description.mkdir(parents=True)
        self.needed = ["app_Core.bundle", "mlx_Cmlx.bundle", "crypto_Crypto.bundle"]
        for name in self.needed + ["app_Eval.bundle"]:
            (self.products / name).mkdir()
        (self.products / "mlx_Cmlx.bundle/default.metallib").write_bytes(b"shader")
        (self.products / "app_Eval.bundle/corpus.json").write_text("{}")
        self.request = {
            "configuredTargets": [{"guid": "PACKAGE-PRODUCT:Uttrflow"}],
            "buildCommand": {"command": "build"}, "containerPath": str(ROOT),
            "parameters": {"configurationName": "Release",
                           "arenaInfo": {"buildProductsPath": str(self.products.parent)}}}
        self.write_description()

    def write_description(self):
        (self.description / "build-request.json").write_text(json.dumps(self.request))
        outputs = [str(self.products / "Uttrflow")]
        outputs += [str(self.products / name / "Contents/Resources/resource") for name in self.needed]
        for output in outputs[1:]:
            path = Path(output)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"resource")
        outputs.append(str(self.products / "mlx_Cmlx.bundle/default.metallib"))
        (self.description / "manifest.json").write_text(
            json.dumps({"commands": {"build": {"outputs": outputs}}}))

    def test_packaging_excludes_an_unrelated_cached_corpus(self):
        script = (ROOT / "Scripts/bundle.sh").read_text()
        discovery = script.split("RESOURCE_BUNDLES=()", 1)[1].split("FRAMEWORKS=()", 1)[0]
        command = 'set -euo pipefail\nRESOURCE_BUNDLES=()\n' + discovery
        command += '\nprintf "%s\\n" "${RESOURCE_BUNDLES[@]}"\n'
        app = self.derived / "app"
        resources = app / "Contents/Resources"
        resources.mkdir(parents=True)
        environment = dict(os.environ, PRODUCTS_DIR=str(self.products), BUILD_DESCRIPTION_STARTED="0",
                           DERIVED_DATA=str(self.derived), PACKAGE_ROOT=str(ROOT),
                           SCRIPT_DIR=str(ROOT / "Scripts"), SCHEME="Uttrflow", APP=str(app))
        result = subprocess.run(["bash", "-c", command], env=environment,
                                text=True, capture_output=True, check=True)
        self.assertEqual(set(Path(line).name for line in result.stdout.splitlines()), set(self.needed))
        self.assertEqual((resources / "mlx_Cmlx.bundle/default.metallib").read_bytes(), b"shader")
        self.assertFalse((resources / "app_Eval.bundle").exists())

    def test_missing_required_metal_bundle_fails(self):
        shutil.rmtree(self.products / "mlx_Cmlx.bundle")
        with self.assertRaisesRegex(ValueError, "required build resource is missing"):
            bundle_products.bundle_products(self.description, self.products, "Uttrflow")

    def test_missing_required_metal_file_fails(self):
        (self.products / "mlx_Cmlx.bundle/default.metallib").unlink()
        with self.assertRaisesRegex(ValueError, "required build resource is missing"):
            bundle_products.bundle_products(self.description, self.products, "Uttrflow")

    def test_unrelated_scheme_cannot_supply_the_app_description(self):
        self.request["configuredTargets"] = [{"guid": "PACKAGE-PRODUCT:uttrflow-eval"}]
        self.write_description()
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_description_without_the_app_executable_fails(self):
        (self.description / "manifest.json").write_text(json.dumps({"commands": {}}))
        with self.assertRaisesRegex(ValueError, "does not produce the app executable"):
            bundle_products.bundle_products(self.description, self.products, "Uttrflow")

    def test_other_configuration_cannot_supply_the_app_description(self):
        self.request["parameters"]["configurationName"] = "Debug"
        self.write_description()
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_other_products_directory_cannot_supply_the_description(self):
        self.request["parameters"]["arenaInfo"]["buildProductsPath"] = "/different/products"
        self.write_description()
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_stale_description_cannot_supply_the_app_resources(self):
        request = self.description / "build-request.json"
        os.utime(request, (1, 1))
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow", since=2)

    def test_ambiguous_descriptions_fail_closed(self):
        other = self.description.parent / "other.xcbuilddata"
        other.mkdir()
        request = self.description / "build-request.json"
        duplicate = other / "build-request.json"
        duplicate.write_bytes(request.read_bytes())
        os.utime(duplicate, ns=(request.stat().st_atime_ns, request.stat().st_mtime_ns))
        with self.assertRaisesRegex(ValueError, "ambiguous Xcode build descriptions"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_malformed_description_fails_closed(self):
        (self.description / "build-request.json").write_text("{")
        with self.assertRaises(json.JSONDecodeError):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_framework_resource_bundle_is_selected_from_its_outputs(self):
        self.needed.append("dependency_FrameworkResources.bundle")
        resource = self.products / self.needed[-1]
        resource.mkdir()
        self.write_description()
        self.assertIn(resource, bundle_products.bundle_products(self.description, self.products, "Uttrflow"))

    def test_other_repository_cannot_supply_the_app_description(self):
        self.request["containerPath"] = "/different/repository"
        self.write_description()
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_missing_build_request_fails_closed(self):
        (self.description / "build-request.json").unlink()
        with self.assertRaisesRegex(ValueError, "no matching Xcode build description"):
            bundle_products.select_description(self.derived, ROOT, self.products, "Uttrflow")

    def test_missing_manifest_fails_closed(self):
        (self.description / "manifest.json").unlink()
        with self.assertRaises(FileNotFoundError):
            bundle_products.bundle_products(self.description, self.products, "Uttrflow")


if __name__ == "__main__":
    unittest.main()
