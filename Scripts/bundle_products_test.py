#!/usr/bin/env python3
"""Proves app packaging ignores cached products outside the app build graph."""

import json
import os
import shutil
import subprocess
import tempfile
import time
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

    def native_cli(self, option, path):
        return subprocess.run(["python3", str(ROOT / "Scripts/bundle_products.py"),
                               str(self.derived), str(ROOT), str(self.products), "Uttrflow",
                               f"--since={self.started}", option, str(path)],
                              text=True, capture_output=True)

    def native_snapshot(self):
        self.started = time.time()
        self.snapshot = self.derived / "before.json"
        result = self.native_cli("--snapshot-out", self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)

    def native_use(self, description=None):
        description = description or self.description
        now = time.time_ns()
        os.utime(description, ns=(now, now))

    def test_native_use_selects_reused_metadata_without_latest_fallback(self):
        request = self.description / "build-request.json"
        os.utime(request, (1, 1))
        other = self.description.parent / "newer.xcbuilddata"
        other.mkdir()
        other_request = other / "build-request.json"
        other_request.write_text(json.dumps(self.request))
        (other / "manifest.json").write_text(json.dumps({"commands": {}}))
        self.assertGreater(other_request.stat().st_mtime_ns, request.stat().st_mtime_ns)
        self.native_snapshot()
        before = request.read_bytes(), request.stat().st_mtime_ns
        self.native_use()
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(Path(line).name for line in result.stdout.splitlines()), set(self.needed))
        self.assertEqual((request.read_bytes(), request.stat().st_mtime_ns), before)

    def test_native_use_requires_a_unique_matching_changed_directory(self):
        self.native_snapshot()
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or ambiguous", result.stderr)
        self.native_use()
        other = self.description.parent / "other.xcbuilddata"
        other.mkdir()
        shutil.copyfile(self.description / "build-request.json", other / "build-request.json")
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing or ambiguous", result.stderr)

    def test_native_use_accepts_a_new_matching_description(self):
        saved = self.description.with_suffix(".saved")
        self.description.rename(saved)
        self.native_snapshot()
        self.description.mkdir()
        for path in saved.iterdir():
            if path.is_file():
                shutil.copyfile(path, self.description / path.name)
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_native_use_preserves_request_identity_and_resource_validation(self):
        original = json.dumps(self.request)
        for field in ("repository", "scheme", "configuration", "products", "command"):
            with self.subTest(field=field):
                request = json.loads(original)
                if field == "repository":
                    request["containerPath"] = "/different/repository"
                elif field == "scheme":
                    request["configuredTargets"] = [{"guid": "PACKAGE-PRODUCT:uttrflow-eval"}]
                elif field == "configuration":
                    request["parameters"]["configurationName"] = "Debug"
                elif field == "products":
                    request["parameters"]["arenaInfo"]["buildProductsPath"] = "/different/products"
                else:
                    request["buildCommand"]["command"] = "clean"
                (self.description / "build-request.json").write_text(json.dumps(request))
                self.native_snapshot()
                self.native_use()
                result = self.native_cli("--snapshot", self.snapshot)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("missing or ambiguous", result.stderr)
        (self.description / "build-request.json").write_text(original)
        self.native_snapshot()
        self.native_use()
        (self.products / "mlx_Cmlx.bundle/default.metallib").unlink()
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required build resource is missing", result.stderr)

    def test_native_use_rejects_stale_malformed_snapshots_and_invalid_start(self):
        self.native_snapshot()
        valid = self.snapshot.read_text()
        self.native_use()
        cases = []
        for key, value in (("derived", "/different/derived"), ("entries", []),
                           ("captured_ns", 0), ("captured_ns", True),
                           ("captured_ns", time.time_ns() + 1_000_000_000_000)):
            snapshot = json.loads(valid)
            snapshot[key] = value
            cases.append(snapshot)
        for name, identity in (("../app.xcbuilddata", {}), ("app.xcbuilddata", []),
                               ("app.xcbuilddata", {"device": 1, "inode": True, "mtime_ns": 1}),
                               ("app.xcbuilddata", {"device": 1, "inode": 1, "mtime_ns": -1})):
            snapshot = json.loads(valid)
            snapshot["entries"] = {name: identity}
            cases.append(snapshot)
        for snapshot in cases + [[], None]:
            with self.subTest(snapshot=snapshot):
                self.snapshot.write_text(json.dumps(snapshot))
                result = self.native_cli("--snapshot", self.snapshot)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("bundle products:", result.stderr)
        self.snapshot.write_text(valid)
        os.utime(self.snapshot, (1, 1))
        self.assertNotEqual(self.native_cli("--snapshot", self.snapshot).returncode, 0)
        self.snapshot.write_text(valid)
        for since in ("nan", "inf", "-inf", "-1"):
            with self.subTest(since=since):
                self.started = since
                result = self.native_cli("--snapshot", self.snapshot)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid Xcode description invocation start", result.stderr)

    def test_native_use_rejects_replaced_nonadvancing_future_or_symlink_directories(self):
        self.native_snapshot()
        original = self.snapshot.read_text()
        self.native_use()
        for field in ("device", "inode", "mtime_ns"):
            with self.subTest(field=field):
                snapshot = json.loads(original)
                identity = snapshot["entries"][self.description.name]
                identity[field] = identity[field] + 1 if field != "mtime_ns" else time.time_ns() + 10**12
                self.snapshot.write_text(json.dumps(snapshot))
                result = self.native_cli("--snapshot", self.snapshot)
                self.assertNotEqual(result.returncode, 0)
        self.snapshot.write_text(original)
        now = time.time_ns() + 10**12
        os.utime(self.description, ns=(now, now))
        self.assertNotEqual(self.native_cli("--snapshot", self.snapshot).returncode, 0)
        saved = self.description.with_suffix(".saved")
        self.description.rename(saved)
        self.description.symlink_to(saved, target_is_directory=True)
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid Xcode description directory", result.stderr)
        result = self.native_cli("--snapshot-out", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid Xcode description directory", result.stderr)

    def test_native_use_rejects_incomplete_description_graphs(self):
        self.native_snapshot()
        self.native_use()
        request = self.description / "build-request.json"
        manifest = self.description / "manifest.json"
        request_bytes, manifest_bytes = request.read_bytes(), manifest.read_bytes()
        for missing in (request, manifest):
            with self.subTest(missing=missing.name):
                missing.unlink()
                result = self.native_cli("--snapshot", self.snapshot)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(missing.name, result.stderr)
                request.write_bytes(request_bytes)
                manifest.write_bytes(manifest_bytes)
        manifest.write_text(json.dumps({"commands": {}}))
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not produce the app executable", result.stderr)
        manifest.write_bytes(manifest_bytes)
        shutil.rmtree(self.products / "mlx_Cmlx.bundle")
        result = self.native_cli("--snapshot", self.snapshot)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required build resource is missing", result.stderr)

    def test_native_capture_preserves_build_failure_diagnostics_and_cleans_snapshot(self):
        script = (ROOT / "Scripts/bundle.sh").read_text()
        build = script.split('BUILD_DESCRIPTION_STARTED="$(date +%s)"', 1)[1].split("BUILT_BINARY=", 1)[0]
        snapshots = self.derived / "snapshots"
        snapshots.mkdir()
        environment = dict(os.environ, TMPDIR=str(snapshots), SCHEME="Uttrflow", CONFIGURATION="Release",
                           DERIVED_DATA=str(self.derived), PRODUCTS_DIR=str(self.products),
                           SCRIPT_DIR=str(ROOT / "Scripts"), PACKAGE_ROOT=str(ROOT),
                           BUILD_DESCRIPTION_STARTED="0")
        for status in (0, 7):
            with self.subTest(status=status):
                command = "set -euo pipefail\nfail() { exit 1; }\n"
                payload = ('import json,sys; snapshot=json.load(open(sys.argv[1])); '
                           'assert snapshot["derived"] == sys.argv[2]; '
                           'assert snapshot["entries"] and snapshot["captured_ns"] > 0')
                command += f"xcodebuild() {{ python3 -c '{payload}' "
                command += '"$BUILD_DESCRIPTION_SNAPSHOT" "$DERIVED_DATA" || return 99; '
                command += f"printf 'warning: diagnostic\\n'; return {status}; }}\n"
                command += build + "\nprintf 'selection reached\\n'\n"
                result = subprocess.run(["bash", "-c", command], env=environment,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0 if status == 0 else 1)
                self.assertIn("warning: diagnostic", result.stdout + result.stderr)
                self.assertEqual("selection reached" in result.stdout, status == 0)
                self.assertEqual(list(snapshots.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
