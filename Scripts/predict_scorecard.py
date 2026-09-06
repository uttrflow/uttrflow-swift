"""Reads a fixture run's JSON and reports what it says about trust.

Precision — right when shown — is the headline, because a person judges the feature by how
often it is wrong when it speaks, not by how often it speaks. Coverage sits beside it, and a
second run may be given to name what a change fixed and what it broke.

    python3 Scripts/predict_scorecard.py new.json [old.json]

The bake-off prints the same headline itself; this adds the per-category breakdown and the
comparison. See Docs/predict-precision.md.
"""
import json
import sys
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
    shown = [r for r in results if r.get("first") and not str(r.get("first")).startswith("error:")]
    right = sum(1 for r in shown if r["hit"])
    return dict(total=total, hit=hit, conforms=conforms, p50=percentile(lat, 0.5), p95=percentile(lat, 0.95),
                failures=len(firsts), nothing=nothing, errors=errors, wrong=wrong, invented=invented,
                shown=len(shown), right=right)


def by_category(results):
    groups = defaultdict(list)
    for r in results:
        groups[r.get("category") or r["name"].split("/")[0]].append(r)
    return {k: summarise(v) for k, v in sorted(groups.items())}


def main():
    new = rows(sys.argv[1])
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
    if len(sys.argv) > 2:
        old = {r["name"]: r for r in rows(sys.argv[2])}
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
