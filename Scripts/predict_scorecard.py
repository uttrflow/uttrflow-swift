"""Reads a fixture run's JSON and reports what it says about trust.

Precision — right when shown — is the headline, because a person judges the feature by how
often it is wrong when it speaks, not by how often it speaks. Coverage sits beside it, and a
second run may be given to name what a change fixed and what it broke.

    python3 Scripts/predict_scorecard.py new.json [--compare-run old.json]

The bake-off prints the same headline itself; this adds the per-category breakdown and the
comparison. See Docs/predict-precision.md.
"""
import argparse
import json
from collections import Counter, defaultdict


def rows(path):
    data = json.load(open(path))
    return data["results"] if isinstance(data, dict) and "results" in data else data


def pct(n, d):
    return f"{100 * n / d:.0f} %" if d else "-"


def percentile(values, p):
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(p * (len(ordered) - 1))))]


def summarise(results):
    total = len(results)
    hit = sum(1 for r in results if r["hit"])
    conforms = sum(1 for r in results if r["conforms"])
    lat = [r["elapsedMs"] for r in results]
    firsts = [r.get("first") for r in results if not r["hit"]]
    nothing = sum(1 for f in firsts if f in (None, "", "-"))
    errors = sum(1 for f in firsts if isinstance(f, str) and f.startswith("error:"))
    wrong = len(firsts) - nothing - errors
    invented = sum(1 for r in results if r.get("invented"))
    shown = [r for r in results if r.get("judged", False) and r.get("drawn")]
    right = sum(1 for r in shown if r["hit"])
    return dict(total=total, hit=hit, conforms=conforms, p50=percentile(lat, 0.5), p95=percentile(lat, 0.95),
                failures=len(firsts), nothing=nothing, errors=errors, wrong=wrong, invented=invented,
                shown=len(shown), right=right)


def by_category(results):
    groups = defaultdict(list)
    for r in results:
        groups[r.get("category") or r["name"].split("/")[0]].append(r)
    return {k: summarise(v) for k, v in sorted(groups.items())}


def identify_scope(summary, results):
    """Add the measured fixture count and exact fixture-name multiset to a scope."""
    names = sorted(r["name"] for r in results)
    return {**summary, "fixtureCount": len(names), "fixtureNames": names}


def by_source(results):
    groups = defaultdict(list)
    for r in results:
        if r.get("source"):
            groups[r["source"]].append(r)
    return {k: summarise(v) for k, v in sorted(groups.items())}


def policy_status(results, target):
    """Describe whether each judged scope meets the product precision target."""
    scopes = {"overall": summarise(results), **by_category(results)}
    statuses = {}
    for name, summary in scopes.items():
        precision = summary["right"] / summary["shown"] if summary["shown"] else None
        if precision is None:
            statuses[name] = "not measured"
        else:
            statuses[name] = "met" if precision >= target else "not met"
    return statuses


def ratchet(results, baseline):
    """Return violations of the measured precision and wrong-line ratchet."""
    grouped = defaultdict(list)
    for result in results:
        grouped[result.get("category") or result["name"].split("/")[0]].append(result)
    current = {
        "overall": identify_scope(summarise(results), results),
        **{name: identify_scope(summarise(rows), rows) for name, rows in sorted(grouped.items())},
    }
    if baseline.get("schemaVersion") != 2:
        return ["recorded baseline lacks fixture identities; re-record it with schema version 2"]
    expected = {"overall": baseline["overall"], **baseline["categories"]}
    failures = []
    if set(current) != set(expected):
        failures.append("fixture categories differ from the recorded baseline")
    for name, measured in current.items():
        previous = expected.get(name)
        if previous is None:
            continue
        current_names = measured.get("fixtureNames")
        expected_names = previous.get("fixtureNames")
        if not isinstance(expected_names, list):
            failures.append(f"{name}: baseline is missing fixture identities")
        else:
            if len(set(current_names)) != len(current_names):
                failures.append(f"{name}: measured fixture names are not unique")
            if len(set(expected_names)) != len(expected_names):
                failures.append(f"{name}: baseline fixture names are not unique")
            if current_names != expected_names:
                missing = len(set(expected_names) - set(current_names))
                unexpected = len(set(current_names) - set(expected_names))
                failures.append(
                    f"{name}: fixture set differs (missing {missing}, unexpected {unexpected})"
                )
        if measured["fixtureCount"] != previous.get("fixtureCount"):
            failures.append(
                f"{name}: fixture count changed {previous.get('fixtureCount')} -> {measured['fixtureCount']}"
            )
        wrong = measured["shown"] - measured["right"]
        previous_wrong = previous["shown"] - previous["right"]
        if wrong > previous_wrong:
            failures.append(f"{name}: wrong shown rose {previous_wrong} -> {wrong}")
        if measured["shown"]:
            precision = measured["right"] / measured["shown"]
            previous_precision = previous["right"] / previous["shown"] if previous["shown"] else None
            if previous_precision is not None and precision < previous_precision:
                failures.append(f"{name}: precision fell {previous_precision:.2%} -> {precision:.2%}")
    return failures


def write_baseline(path, results, minimum_precision, report):
    """Record a measured run as the comparison point for later scorecards."""
    failures = full_catalogue_recording_failures(report, results)
    if failures:
        raise ValueError("; ".join(failures))
    baseline = {
        "schemaVersion": 2,
        "policyTargetPrecision": minimum_precision,
        "overall": identify_scope(summarise(results), results),
        "categories": {
            name: identify_scope(summary, [
                result for result in results
                if (result.get("category") or result["name"].split("/")[0]) == name
            ])
            for name, summary in by_category(results).items()
        },
    }
    with open(path, "w") as handle:
        json.dump(baseline, handle, indent=2, sort_keys=True)
        handle.write("\n")


def full_catalogue_recording_failures(report, results):
    """Refuse to bless partial, filtered, duplicate, or legacy fixture runs as a baseline."""
    if not isinstance(report, dict) or report.get("fullFixtureCatalogue") is not True:
        return ["baseline recording requires an unfiltered full fixture catalogue report"]
    count = report.get("fixtureCatalogueCount")
    if not isinstance(count, int) or count != len(results):
        return ["baseline recording requires every fixture in the reported catalogue"]
    summary = report.get("summary")
    if not isinstance(summary, dict) or summary.get("total") != len(results):
        return ["baseline recording requires a consistent fixture summary"]
    names = [result.get("name") for result in results]
    if any(not isinstance(name, str) or not name for name in names):
        return ["baseline recording requires a name for every fixture"]
    if len(set(names)) != len(names):
        return ["baseline recording refuses duplicate fixture names"]
    return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", help="fixture run JSON")
    parser.add_argument("--baseline", help="compare against a recorded scorecard baseline")
    parser.add_argument("--compare-run", help="show fixture-level changes against another run JSON")
    parser.add_argument("--record-baseline", help="write this run as the reviewed baseline")
    parser.add_argument("--minimum-precision", type=float, default=0.99)
    args = parser.parse_args()
    with open(args.run) as handle:
        run_report = json.load(handle)
    new = run_report["results"] if isinstance(run_report, dict) and "results" in run_report else run_report
    s = summarise(new)
    print(f"cases {s['total']}  hit {s['hit']} ({pct(s['hit'], s['total'])})  in register {s['conforms']} "
          f"({pct(s['conforms'], s['total'])})  p50 {s['p50']} ms  p95 {s['p95']} ms")
    print(f"failures {s['failures']}: nothing {s['nothing']}, errors {s['errors']}, wrong {s['wrong']}  "
          f"invented (written, then denied) {s['invented']}")
    wrong_shown = s["shown"] - s["right"]
    precision = f"{100 * s['right'] / s['shown']:.2f} %" if s["shown"] else "-"
    print(f"precision {precision} ({s['right']}/{s['shown']} shown, {wrong_shown} wrong)  "
          f"coverage {pct(s['shown'], s['total'])}")
    print("\nby category:")
    for k, v in by_category(new).items():
        print(f"  {k:10s} n={v['total']:4d} hit {pct(v['hit'], v['total']):>5}  register {pct(v['conforms'], v['total']):>5}  "
              f"p50 {v['p50']:4d}  precision {(f'{100 * v['right'] / v['shown']:.1f}%' if v['shown'] else '-'):>7}  "
              f"wrong {v['shown'] - v['right']:3d}  quiet {v['total'] - v['shown']:3d}")
    sources = by_source(new)
    if sources:
        print("\nby shown source:")
        for k, v in sources.items():
            wrong = v["shown"] - v["right"]
            precision = f"{100 * v['right'] / v['shown']:.2f} %" if v["shown"] else "-"
            print(f"  {k:12s} precision {precision:>8} ({v['right']}/{v['shown']} shown, {wrong} wrong)")
        unjudged = defaultdict(int)
        for row in new:
            shown = bool(row.get("drawn"))
            if row.get("source") and shown and not row.get("judged", False):
                unjudged[row["source"]] += 1
        if unjudged:
            print("unjudged shown lines by source:")
            for k, count in sorted(unjudged.items()):
                print(f"  {k:12s} {count}")
    if args.baseline:
        with open(args.baseline) as handle:
            baseline = json.load(handle)
        failures = ratchet(new, baseline)
        print("\nprecision ratchet:")
        print("  PASS" if not failures else "\n".join(f"  FAIL {failure}" for failure in failures))
        target = baseline["policyTargetPrecision"]
        print(f"  policy precision target: {100 * target:.2f}%")
        scopes = {"overall": s, **by_category(new)}
        for name, status in policy_status(new, target).items():
            if status == "not measured":
                print(f"  TARGET NOT MEASURED {name}: no judged suggestions shown")
            else:
                measured = scopes[name]
                precision = measured["right"] / measured["shown"]
                label = "TARGET MET" if status == "met" else "TARGET NOT MET"
                print(f"  {label} {name}: measured {precision:.2%}")
        if failures:
            raise SystemExit(1)
    if args.record_baseline:
        recording_failures = full_catalogue_recording_failures(run_report, new)
        if recording_failures:
            for failure in recording_failures:
                print(f"\nbaseline recording refused: {failure}")
            raise SystemExit(1)
        write_baseline(args.record_baseline, new, args.minimum_precision, run_report)
        print(f"\nwritten measured baseline to {args.record_baseline}")
    if args.compare_run:
        old = {r["name"]: r for r in rows(args.compare_run)}
        fixed = [r for r in new if r["hit"] and r["name"] in old and not old[r["name"]]["hit"]]
        broke = [r for r in new if not r["hit"] and r["name"] in old and old[r["name"]]["hit"]]
        print(f"\nvs old: fixed {len(fixed)}, regressed {len(broke)}")
        for r in broke[:40]:
            print(f"  REGRESSED {r['name']:45s} typed={r['typed']!r:30} first={r.get('first')!r}  was={old[r['name']].get('first')!r}")
    print("\nremaining failures by first-answer shape:")
    shapes = Counter()
    for r in new:
        if r["hit"]:
            continue
        f = r.get("first")
        shapes["nothing" if f in (None, "", "-") else ("error" if str(f).startswith("error:") else "wrong")] += 1
    print(" ", dict(shapes))
    print("\nsample wrong answers:")
    for r in [r for r in new if not r["hit"] and r.get("first") not in (None, "", "-")][:30]:
        print(f"  {r['name']:45s} typed={r['typed']!r:32} first={r.get('first')!r}")


if __name__ == "__main__":
    main()
