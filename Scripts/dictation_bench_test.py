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

    def test_every_clip_tags_only_entities_its_written_text_contains_with_or_without_a_vocabulary(self):
        made = bench.clips()
        nouns = {c["id"]: c for c in made if c["category"] in ("nouns", "nouns-vocabulary")}
        for c in made:
            for e in c["entities"]:
                self.assertIn(e, c["written"], c["id"])
        bare = next(c for c in nouns.values() if not c["vocabulary"])
        self.assertEqual(bare["entities"], nouns[bare["id"] + "-vocabulary"]["entities"])
        self.assertTrue(bare["entities"])

    def test_entity_error_counts_a_term_with_any_word_wrong_and_tagged_words_apart_from_the_rest(self):
        clip = dict(CLIP, written="run git push now", spoken="run git push now", entities=["git push"])
        counts = bench.entity_counts(clip, "run git push now", "ran get push now")
        self.assertEqual((counts["entities"], counts["entity_missed"]), (1, 1))
        self.assertEqual((counts["tagged"], counts["tagged_wrong"]), (2, 1))
        self.assertEqual((counts["untagged"], counts["untagged_wrong"]), (2, 1))

    def test_a_false_override_is_a_word_the_decoder_had_right_and_the_final_text_does_not(self):
        clip = dict(CLIP, written="open the json file", spoken="open the json file", entities=["json"])
        counts = bench.entity_counts(clip, "open the jason file", "open a jason file")
        self.assertEqual((counts["decoder_right"], counts["overridden"]), (3, 1))
        self.assertTrue(counts["compared"])

    def test_a_false_override_is_not_counted_where_the_spoken_and_written_forms_differ(self):
        clip = dict(CLIP, written="--force", spoken="dash dash force", entities=["--force"])
        counts = bench.entity_counts(clip, "dash dash force", "dash dash force")
        self.assertFalse(counts["compared"])
        self.assertEqual(counts["decoder_right"], 0)

    def test_a_score_prints_entity_metrics_sliced_by_category_and_vocabulary(self):
        clips = [dict(CLIP, id="with", category="nouns-vocabulary", vocabulary=["Pravix"], entities=["Pravix"],
                      spoken="meet Pravix today", written="meet Pravix today"),
                 dict(CLIP, id="without", category="nouns", entities=["Pravix"],
                      spoken="meet Pravix today", written="meet Pravix today")]
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump(clips, handle)
        right = result_event("with", text="meet Pravix today")
        right["events"][0]["text"] = "meet Pravix today"
        wrong = result_event("without", text="meet previous today")
        wrong["events"][0]["text"] = "meet Pravix today"
        out = self.run_bench("score", self.write_run("BENCH " + json.dumps(right), "BENCH " + json.dumps(wrong)))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("| nouns, no vocabulary | 1 | 100.0% | 100.0% | 0.0% | 33.3% | 1 |", out.stdout)
        self.assertIn("| nouns-vocabulary, vocabulary | 1 | 0.0% | 0.0% | 0.0% | 0.0% | 1 |", out.stdout)

    def test_every_domain_sentence_is_read_bare_and_with_its_own_terms_by_every_voice(self):
        made = [c for c in bench.clips() if c.get("domain")]
        for domain, rows in bench.DOMAINS.items():
            mine = [c for c in made if c["category"] == f"domain-{domain}"]
            terms = {t for c in mine for t in c["entities"]}
            self.assertGreaterEqual(len(terms), bench.DOMAIN_MIN_TERMS, domain)
            self.assertGreaterEqual(len(rows), bench.DOMAIN_MIN_SENTENCES, domain)
            bases = {}
            for c in mine:
                bases.setdefault(c["id"].rsplit("-", 1)[0], {})[c["domain_condition"]] = c
            self.assertEqual(len(bases), len(rows) * len(bench.ENGLISH), domain)
            for base, conditions in bases.items():
                self.assertEqual(set(conditions), set(bench.DOMAIN_CONDITIONS), base)
                bare, supplied = conditions["bare"], conditions["vocabulary"]
                self.assertEqual(bare["vocabulary"], [], base)
                self.assertEqual(supplied["vocabulary"], supplied["entities"], base)
                self.assertEqual(bare["entities"], supplied["entities"], base)
                self.assertEqual(bare["say"], supplied["say"], base)

    def test_a_domain_sentence_with_a_term_missing_from_its_written_text_fails_loudly(self):
        rows = [(None, "Start metformin today.", ["metformin", "warfarin"])] * bench.DOMAIN_MIN_SENTENCES
        original = bench.DOMAINS
        bench.DOMAINS = {"medical": rows}
        self.addCleanup(setattr, bench, "DOMAINS", original)
        with self.assertRaisesRegex(ValueError, "warfarin"):
            bench.clips()

    def test_a_domain_with_fewer_terms_than_the_minimum_fails_loudly(self):
        rows = [(None, f"Start drug{i} today.", [f"drug{i}"]) for i in range(bench.DOMAIN_MIN_SENTENCES)]
        original = bench.DOMAINS
        bench.DOMAINS = {"medical": rows}
        self.addCleanup(setattr, bench, "DOMAINS", original)
        with self.assertRaisesRegex(ValueError, "fewer than"):
            bench.clips()

    def test_a_domain_score_reports_term_error_without_and_with_the_vocabulary(self):
        clips = [dict(CLIP, id=f"dm-{condition}", category="domain-medical", vocabulary=vocabulary,
                      entities=["apixaban"], spoken="continue the apixaban", written="continue the apixaban",
                      domain="medical", domain_condition=condition)
                 for condition, vocabulary in (("bare", []), ("vocabulary", ["apixaban"]))]
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump(clips, handle)
        bare = result_event("dm-bare", text="continue the a pixaban")
        bare["events"][0]["text"] = "continue the a pixaban"
        supplied = result_event("dm-vocabulary", text="continue the apixaban")
        supplied["events"][0]["text"] = "continue the apixaban"
        out = self.run_bench("score", self.write_run("BENCH " + json.dumps(bare), "BENCH " + json.dumps(supplied)))
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("| domain-medical, no vocabulary | 1 | 100.0% |", out.stdout)
        self.assertIn("| domain-medical, vocabulary | 1 | 0.0% |", out.stdout)

    def test_every_persona_sentence_is_scored_off_on_and_with_another_personas_vocabulary(self):
        made = [c for c in bench.clips() if c.get("persona")]
        own = {name: vocabulary for name, _, vocabulary, _ in bench.PERSONAS}
        bases = {}
        for c in made:
            bases.setdefault(c["id"].rsplit("-", 1)[0], {})[c["persona_condition"]] = c
            self.assertEqual(c["entities"], [e for e in own[c["persona"]] if e in c["written"]], c["id"])
            self.assertTrue(c["entities"], c["id"])
        self.assertEqual(len(bases), sum(len(p[3]) for p in bench.PERSONAS) * len(bench.ENGLISH))
        for base, conditions in bases.items():
            self.assertEqual(set(conditions), set(bench.PERSONA_CONDITIONS), base)
            persona = conditions["on"]["persona"]
            self.assertEqual(conditions["off"]["vocabulary"], [], base)
            self.assertEqual(conditions["on"]["vocabulary"], own[persona], base)
            self.assertIn(conditions["wrong"]["vocabulary"], [v for n, v in own.items() if n != persona], base)
            self.assertFalse(set(conditions["wrong"]["vocabulary"]) & set(own[persona]), base)
            self.assertEqual(len({c["say"] for c in conditions.values()}), 1, base)

    def test_a_persona_job_names_the_app_it_dictates_into(self):
        clip = dict(CLIP, id="persona", vocabulary=["Quillmark"], app="com.apple.Terminal")
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump([clip], handle)
        run = self.run_bench("jobs")
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(run.stdout.rstrip("\n").split("\t")[2:], ["Quillmark", "fast", "shipping", "en",
                                                                     "com.apple.Terminal"])

    def persona_run(self, wrong_text):
        said = "ask Quillmark to merge the branch today"
        clips = [dict(CLIP, id=f"persona-dev0-samantha-{k}", category="persona-dev", persona="dev",
                      persona_condition=k, app="com.apple.Terminal", entities=["Quillmark"], spoken=said,
                      written=said, vocabulary=[] if k == "off" else ["Quillmark"])
                 for k in bench.PERSONA_CONDITIONS]
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump(clips, handle)
        texts = {"off": "ask quill mark to merge the branch today", "on": said, "wrong": wrong_text}
        events = []
        for k, text in texts.items():
            event = result_event(f"persona-dev0-samantha-{k}", text=text)
            event["events"][0]["text"] = text
            events.append("BENCH " + json.dumps(event))
        return self.run_bench("score", self.write_run(*events))

    def test_a_persona_score_reports_gain_with_the_right_vocabulary_and_passes_when_the_wrong_one_costs_nothing(self):
        out = self.persona_run("ask quill mark to merge the branch today")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("| dev | com.apple.Terminal | 1 | 28.6% | 0.0% | 28.6% | 100.0% | 0.0% | 100.0% | +28.6 | +0.0 |",
                      out.stdout)
        self.assertIn("| persona-dev, persona wrong | 1 | 100.0% |", out.stdout)

    def test_a_persona_score_fails_when_the_wrong_vocabulary_harms_beyond_the_limit(self):
        out = self.persona_run("ask quill mark to merge the brunch Tuesday")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn("| 28.6% | 0.0% | 57.1% | 100.0% | 0.0% | 100.0% | +28.6 | +28.6 |", out.stdout)
        self.assertIn("persona harm over 2.0 points: dev, cleaner shipping, mode fast", out.stdout)

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

    # baseline compare

    def judge(self, run, baseline, *flags):
        return self.run_bench("score", run, "--baseline", baseline, *flags)

    def test_a_saved_baseline_passes_the_same_run_and_fails_a_worse_one(self):
        # The paired bootstrap rules on a slice only with two utterances or more.
        with open(os.path.join(self.out, "corpus.json"), "w") as handle:
            json.dump([CLIP, dict(CLIP, id="second", wav="second.wav")], handle)
        good = self.write_run(*("BENCH " + json.dumps(result_event(i)) for i in ("known", "second")))
        baseline = os.path.join(self.out, "baseline.json")
        saved = self.judge(good, baseline, "--save-baseline")
        self.assertEqual(saved.returncode, 0, saved.stderr)
        self.assertEqual(json.load(open(baseline))["entries"][0]["referenceWordCount"], 2)
        same = self.judge(good, baseline, "--fail-on-regression")
        self.assertEqual(same.returncode, 0, same.stdout + same.stderr)
        self.assertIn("verdict: no change detectable", same.stdout)
        worse = self.write_run(*("BENCH " + json.dumps(result_event(i, text="Hello there.")) for i in ("known", "second")))
        judged = self.judge(worse, baseline, "--fail-on-regression")
        self.assertNotEqual(judged.returncode, 0)
        self.assertIn("verdict: worsened", judged.stdout)

    def test_a_run_mixing_cleaners_is_refused_rather_than_judged_as_one(self):
        rules = dict(result_event("known"), cleaner="rules")
        run = self.write_run("BENCH " + json.dumps(result_event("known")), "BENCH " + json.dumps(rules))
        judged = self.judge(run, os.path.join(self.out, "b.json"), "--save-baseline")
        self.assertNotEqual(judged.returncode, 0)
        self.assertIn("one cleaner and mode", judged.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=1)
