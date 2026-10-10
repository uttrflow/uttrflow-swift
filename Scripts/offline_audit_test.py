#!/usr/bin/env python3
"""Proves the offline audit's source checks fail on each way of reaching the network."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# The audit's own headline for each source check, matched against its output.
NETWORK_FAILURE = "a network call site appeared outside the files allowed one"
URL_READ_FAILURE = "a new URL read appeared"
MISSING_ALLOWANCE = "an allowed network path no longer exists"
UPDATER_FAILURE = "the updater is imported outside the app shell"
TRANSPORT_FAILURE = "a network transport is no longer bound to request counting"

# One line of Swift per way in, and the module to put it in. The modules are the ones the
# audit did not cover before #665, so a narrowing of its coverage fails here.
WAYS_IN = {
    "URLSession": ("UttrflowClipboard", "let session = URLSession.shared\n"),
    "Network.framework": ("UttrflowHistory", "import Network\n"),
    "a raw socket": ("UttrflowPredict", "let fd = socket(AF_INET, SOCK_STREAM, 0)\n"),
    "a Darwin BSD socket": ("UttrflowPredict", "let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)\n"),
    "a raw BSD connect": ("UttrflowPredict", "connect(fd, addr, len)\n"),
    "a Darwin BSD connect": ("UttrflowPredict", "Darwin.connect(fd, addr, len)\n"),
    "a Glibc BSD connect": ("UttrflowPredict", "Glibc.connect(fd, addr, len)\n"),
    "a name lookup": ("UttrflowPredictStore", "let e = getaddrinfo(h, nil, nil, nil)\n"),
    "a system asset install": ("UttrflowDictionary", "try await request.downloadAndInstall()\n"),
    "an endpoint literal": ("UttrflowSettings", 'let host = "https://example.com/v1"\n'),
    "XPC to a helper": ("UttrflowUX", 'let c = NSXPCConnection(serviceName: "x")\n'),
    "MLX's distributed backend": ("UttrflowLocalModel", "mlx_distributed_init(false, b)\n"),
}


class Workspace:
    """A copy of Sources and the audit, with an xcrun that fails so no build is attempted."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="uttrflow-offline-")
        os.makedirs(os.path.join(self.root, "Scripts"))
        os.makedirs(os.path.join(self.root, "bin"))
        shutil.copy(os.path.join(HERE, "offline_audit.sh"), os.path.join(self.root, "Scripts"))
        shutil.copy(os.path.join(ROOT, "Package.swift"), self.root)
        shutil.copytree(os.path.join(ROOT, "Sources"), os.path.join(self.root, "Sources"))
        # The binary half needs a built app, which a copied tree has not got. A stub that
        # fails stops it reaching for the network to resolve a package graph; every
        # assertion below is on a source check's own message, not on the exit status.
        stub = os.path.join(self.root, "bin", "xcrun")
        with open(stub, "w") as handle:
            handle.write("#!/bin/sh\nexit 1\n")
        os.chmod(stub, 0o755)

    def write(self, module, text):
        path = os.path.join(self.root, "Sources", module, "AuditProbe.swift")
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def remove_transport_marker(self, relative_path, marker):
        path = os.path.join(self.root, relative_path)
        with open(path) as handle:
            original = handle.read()
        self.assert_marker_present(original, marker, relative_path)
        with open(path, "w") as handle:
            handle.write(original.replace(marker, "", 1))
        return path, original

    @staticmethod
    def assert_marker_present(source, marker, relative_path):
        if marker not in source:
            raise AssertionError(f"{relative_path} no longer contains {marker}")

    def output(self):
        environment = dict(os.environ, PATH=os.path.join(self.root, "bin") + os.pathsep + os.environ["PATH"])
        finished = subprocess.run(
            ["bash", os.path.join("Scripts", "offline_audit.sh"), "--no-build"],
            cwd=self.root, capture_output=True, text=True, env=environment,
        )
        return finished.stdout + finished.stderr

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class OfflineAuditTests(unittest.TestCase):
    """One workspace for the class: the audit reads the tree and never writes to it."""

    @classmethod
    def setUpClass(cls):
        cls.workspace = Workspace()

    @classmethod
    def tearDownClass(cls):
        cls.workspace.close()

    def tearDown(self):
        for module in {module for module, _ in WAYS_IN.values()} | {"UttrflowAccount"}:
            probe = os.path.join(self.workspace.root, "Sources", module, "AuditProbe.swift")
            if os.path.exists(probe):
                os.remove(probe)

    def test_audio_engine_wiring_is_not_a_network_offender(self):
        output = self.workspace.output()
        self.assertNotIn("Sources/UttrflowAudio/CueEngineWiring.swift", output)

    def test_every_way_in_is_refused(self):
        for way, (module, line) in WAYS_IN.items():
            with self.subTest(way=way):
                self.workspace.write(module, line)
                output = self.workspace.output()
                self.assertIn(NETWORK_FAILURE, output, f"{way} in {module} went unnoticed")
                self.assertIn(f"Sources/{module}/AuditProbe.swift", output)
                self.tearDown()

    def test_reading_a_url_is_refused(self):
        self.workspace.write("UttrflowClipboard", "let d = try Data(contentsOf: url)\n")
        output = self.workspace.output()
        self.assertIn(URL_READ_FAILURE, output)
        self.assertIn("Sources/UttrflowClipboard/AuditProbe.swift", output)

    def test_eval_accuracy_history_is_an_explicit_reader_allowance(self):
        reader = os.path.join(self.workspace.root, "Sources", "UttrflowEval", "AccuracyReport.swift")
        with open(reader) as handle:
            self.assertIn("Data(contentsOf: url)", handle.read())

        audit = os.path.join(self.workspace.root, "Scripts", "offline_audit.sh")
        with open(audit) as handle:
            original = handle.read()
        allowance = "    'Sources/UttrflowEval/AccuracyReport.swift'\n"
        self.assertIn(allowance, original)
        with open(audit, "w") as handle:
            handle.write(original.replace(allowance, "", 1))
        try:
            output = self.workspace.output()
            self.assertIn(URL_READ_FAILURE, output)
            self.assertIn("Sources/UttrflowEval/AccuracyReport.swift", output)
        finally:
            with open(audit, "w") as handle:
                handle.write(original)

    def test_the_account_module_is_still_allowed_one(self):
        self.workspace.write("UttrflowAccount", "let session = URLSession.shared\n")
        self.assertNotIn("Sources/UttrflowAccount/AuditProbe.swift", self.workspace.output())

    def test_audio_engine_connect_is_not_a_bsd_socket_call(self):
        self.workspace.write("UttrflowAudio", "engine.connect(a, to: b, format: f)\n")
        self.assertNotIn("Sources/UttrflowAudio/AuditProbe.swift", self.workspace.output())

    def test_an_allowance_that_names_a_missing_file_is_refused(self):
        island = os.path.join(self.workspace.root, "Sources", "UttrflowSpeech", "TokenizerDownload.swift")
        moved = island + ".moved"
        os.rename(island, moved)
        try:
            self.assertIn(MISSING_ALLOWANCE, self.workspace.output())
        finally:
            os.rename(moved, island)

    def test_the_updater_outside_the_app_shell_is_refused(self):
        self.workspace.write("UttrflowUX", "import Sparkle\n")
        self.assertIn(UPDATER_FAILURE, self.workspace.output())

    def test_every_transport_binding_is_required(self):
        bindings = [
            ("Sources/UttrflowAccount/BackendTransport+URLSession.swift", "ledger.record(request.purpose)"),
            ("Sources/UttrflowSpeech/TokenizerDownload.swift", "private func recordSpeechAssetRequest()"),
            ("Sources/UttrflowSpeech/TokenizerDownload.swift", "private func countedTokenizerData("),
            ("Sources/UttrflowLocalModel/AnonymousHub.swift", "func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask)"),
            ("Sources/UttrflowLocalModel/AnonymousHub.swift", "willPerformHTTPRedirection"),
            ("Sources/UttrflowDiagnostics/CrashReporter.swift", "options.urlSession = CrashReportSession.make()"),
            ("Sources/UttrflowDiagnostics/CrashReporter.swift", "private func countCreatedCrashRequest()"),
            ("Sources/UttrflowDiagnostics/CrashReporter.swift", "private func countRedirectedCrashRequest()"),
            ("Sources/Uttrflow/Updates/UpdateController.swift", "requestActivity.feedLoaded()"),
            ("Sources/Uttrflow/Updates/UpdateController.swift", "requestActivity.feedFailed()"),
            ("Sources/Uttrflow/Updates/UpdateController.swift", "requestActivity.archiveWillDownload()"),
            ("Sources/Uttrflow/Updates/UpdateController.swift", "requestActivity.checkDidFinish()"),
            ("Sources/Uttrflow/Updates/UpdateRequestActivity.swift", "let feedWasCounted = Mutex(false)"),
            ("Sources/Uttrflow/Updates/UpdateRequestActivity.swift", "guard !wasCounted else { return false }"),
            ("Sources/Uttrflow/Updates/UpdateRequestActivity.swift", "if shouldRecord { ledger.record(.updateCheck) }"),
        ]
        for relative_path, marker in bindings:
            with self.subTest(relative_path=relative_path, marker=marker):
                path, original = self.workspace.remove_transport_marker(relative_path, marker)
                try:
                    output = self.workspace.output()
                    self.assertIn(TRANSPORT_FAILURE, output)
                    self.assertIn(relative_path, output)
                finally:
                    with open(path, "w") as handle:
                        handle.write(original)


if __name__ == "__main__":
    unittest.main(verbosity=0 if "-q" in sys.argv else 1)
