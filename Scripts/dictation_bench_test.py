#!/usr/bin/env python3
"""Proves `jobs` and `score` fail loudly on an empty selection or an empty run, instead of exiting 0."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.join(HERE, "dictation_bench.py")
TABLE = os.path.join(os.path.dirname(HERE), "Tests", "UttrflowEvalTests", "Golden", "normalisation.tsv")
sys.path.insert(0, HERE)
import dictation_bench as bench  # noqa: E402

CLIP = {
    "id": "known",
    "wav": "known.wav",
    "vocabulary": [],
    "category": "reply",
    "variant": "clean",
    "language": "english",
    "voice": "Samantha",
    "spoken": "hello world",
    "written": "Hello world.",
    "devanagari": None,
}


def result_event(clip_id, text="Hello world."):
    return {
        "event": "result",
        "id": clip_id,
        "text": text,
        "events": [
            {"kind": "asr", "text": "hello world", "t0": 0, "t1": 1},
            {"kind": "clean", "t0": 1, "t1": 1.2},
            {"kind": "keyup", "t": 1.5},
        ],
        "wait": 0.1,
        "audio": 1.0,
        "cpu": 0.1,
        "peakMB": 50,
        "cleaner": "shipping",
        "mode": "fast",
    }


class BenchTests(unittest.TestCase):
    def setUp(self):
        self.out = tempfile.mkdtemp(prefix="uttrflow-bench-")
        self.addCleanup(shutil.rmtree, self.out, ignore_errors=True)
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump([CLIP], handle)

    def run_bench(self, *args):
        return subprocess.run(
            [sys.executable, BENCH, "--out", self.out, *args],
            capture_output=True, text=True,
        )

    def write_run(self, *lines):
        path = os.path.join(self.out, "run.jsonl")
        with open(path, "w") as handle:
            for line in lines:
                handle.write(line + "\n")
        return path

    def test_normalisation_matches_the_table_the_swift_scorer_is_pinned_to(self):
        with open(TABLE, encoding="utf-8") as handle:
            rows = [line.rstrip("\n").split("\t") for line in handle if line.strip()]
        self.assertTrue(rows)
        for text, words in rows:
            self.assertEqual(bench.normalise(text), words.split(), text)

    def test_devanagari_matra_errors_are_counted_as_word_edits(self):
        self.assertEqual(
            bench.errors(
                ["कल शाम को मैं घर जल्दी पहुँच गया"],
                "कल शाम को मै घर जल्दी पहुंच गया",
            ),
            (2, 8),
        )

    def test_an_extra_devanagari_word_is_counted(self):
        self.assertEqual(
            bench.errors(["मैं नहीं आऊँगा"], "मैं नहीं आऊँगा बिल्कुल"),
            (1, 3),
        )

    def test_a_number_written_as_digits_or_words_scores_the_same(self):
        self.assertEqual(
            bench.errors(["Hello, world! I paid three dollars."], "Hello world, I paid 4 dollars."),
            (1, 6),
        )

    def test_a_removed_filler_scores_as_correct_against_the_written_reference(self):
        restarts = next(c for c in bench.clips() if c["id"] == "tc-en-restarts-samantha")
        self.assertIn("um,", restarts["spoken"])
        self.assertNotIn("um", bench.normalise(restarts["written"]))
        cleaned = restarts["spoken"].replace("and, um, nobody", "and nobody")
        self.assertEqual(bench.errors([restarts["written"]], cleaned)[0], 0)

    def test_a_written_edit_that_no_longer_matches_fails_loudly(self):
        with self.assertRaises(ValueError):
            bench.written_for("en-restarts", "a passage without the filler")

    def test_a_listed_spelling_variant_is_not_an_error(self):
        ref = "Someone uses the thick card stock."
        self.assertEqual(bench.errors([ref], "Someone uses the thick cardstock.")[0], 0)
        self.assertEqual(bench.errors([ref], "Someone uses the thick cardstock.", words=bench.exact_words)[0], 0)

    def test_exact_scoring_counts_case_marks_and_symbols_that_normalised_scoring_hides(self):
        for written, heard in (("git checkout -b", "git checkout-b"), ("cargo build --release", "cargo build - release"),
                               ("call useState here", "call use state here"),
                               ("git push origin main", "Git push origin main."),
                               ("send it to the team", "send it to The team")):
            self.assertEqual(bench.errors([written], heard)[0], 0, heard)
            self.assertGreater(bench.errors([written], heard, words=bench.exact_words)[0], 0, heard)

    def test_a_score_reports_normalised_and_exact_final_rates(self):
        out = self.run_bench("score", self.write_run("BENCH " + json.dumps(result_event("known", text="hello world"))))
        self.assertIn("final exact WER", out.stdout)
        self.assertIn("| reply | 1 | 0.0% | 0.0% | 100.0% |", out.stdout)

    def test_every_developer_vocabulary_category_has_paired_bare_and_context_clips(self):
        made = [c for c in bench.clips() if c["category"].startswith("devvocab-")]
        for kind in bench.DEVVOCAB:
            mine = [c for c in made if c["category"] == f"devvocab-{kind}"]
            bare = {c["id"].rsplit("-", 1)[0] for c in mine if c["context"] == "bare"}
            context = {c["id"].rsplit("-", 1)[0] for c in mine if c["context"] == "context"}
            self.assertEqual(bare, context, kind)
            self.assertGreaterEqual(len(bare), bench.DEVVOCAB_MIN_CASES * len(bench.ENGLISH), kind)
        for c in made:
            self.assertIn(c["term"], c["written"], c["id"])

    def test_a_paired_score_reports_whether_the_term_was_heard_bare_and_after_the_lead_in(self):
        clips = [dict(CLIP, id="dv-bare", category="devvocab-commands", context="bare", term="git push",
                      spoken="git push", written="git push"),
                 dict(CLIP, id="dv-context", category="devvocab-commands", context="context", term="git push",
                      spoken="In the terminal, run git push.", written="In the terminal, run git push.")]
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump(clips, handle)
        bare = result_event("dv-bare", text="get push")
        bare["events"][0]["text"] = "get push"
        context = result_event("dv-context", text="In the terminal, run git push.")
        context["events"][0]["text"] = "In the terminal, run git push."
        out = self.run_bench("score", self.write_run("BENCH " + json.dumps(bare), "BENCH " + json.dumps(context)))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("| devvocab-commands | 1 | 50.0% | 0.0% | 0/1 | 1/1 |", out.stdout)

    # jobs

    def test_a_matching_category_produces_jobs(self):
        run = self.run_bench("jobs", "--categories", "reply")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("known", run.stdout)

    def test_a_category_typo_that_selects_nothing_fails_instead_of_printing_a_blank_line(self):
        run = self.run_bench("jobs", "--categories", "typo")
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn("known", run.stdout)

    # score

    def test_a_valid_run_is_scored_and_exits_zero(self):
        run_path = self.write_run("BENCH " + json.dumps(result_event("known")))
        run = self.run_bench("score", run_path)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn("failed: none", run.stdout)

    def test_an_empty_run_file_fails_instead_of_printing_failed_none(self):
        run_path = self.write_run()
        run = self.run_bench("score", run_path)
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn("failed: none", run.stdout)

    def test_an_unknown_result_id_is_reported_and_fails_when_nothing_else_scores(self):
        run_path = self.write_run("BENCH " + json.dumps(result_event("unknown-clip")))
        run = self.run_bench("score", run_path)
        self.assertNotEqual(run.returncode, 0)
        combined = run.stdout + run.stderr
        self.assertIn("unknown-clip", combined)


if __name__ == "__main__":
    unittest.main(verbosity=1)
