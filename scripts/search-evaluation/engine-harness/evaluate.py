#!/usr/bin/env python3
"""Replay the three search sets straight against the engine source, without a simulator.

Builds the engine with swiftc, then scores the development set, the validation recovery set and the
annual replay. Best matches are graded as the result list. Close matches count only for the
"no false empty" and top-3 measures, because the screen shows them under their own heading.
"""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import date, timedelta
import gzip

HERE = Path(__file__).resolve().parent
EVALUATION = HERE.parent
ROOT = EVALUATION.parent.parent
sys.path.insert(0, str(EVALUATION))

from check_recovery import check  # noqa: E402
from score import success  # noqa: E402
import year_grader  # noqa: E402
from year_study import prepare  # noqa: E402

SOURCES = ["WorkoutSearchEngine.swift", "WorkoutSearchVocabulary.swift", "WorkoutSearchScoring.swift", "WorkoutSearchMeanings.swift", "WorkoutSearchMoments.swift"]


def build(work):
    binary = work / "harness"
    product = ROOT / "WindRun/Features/Progress"
    files = [str(product / name) for name in SOURCES] + [str(HERE / "Stubs.swift"), str(HERE / "main.swift")]
    subprocess.run(["swiftc", "-O", "-swift-version", "5", "-enable-bare-slash-regex", "-default-isolation", "MainActor", *files, "-o", str(binary)], check=True)
    return binary


def replay(binary, corpus, work, name):
    source, output = work / f"{name}.json", work / f"{name}-observations.json"
    source.write_text(json.dumps(corpus))
    subprocess.run([str(binary), str(source), str(output)], check=True)
    if ARGS.debug: print(name)
    return {row["queryID"]: row for row in json.loads(output.read_text())}


def split(binary, work, name):
    folder = work / name
    subprocess.run([sys.executable, str(EVALUATION / "corpus.py"), "export", "--split", name,
                    "--output", str(folder / "corpus.json")], check=True, stdout=subprocess.DEVNULL)
    inputs = json.loads((folder / "corpus.json").read_text())
    gold = json.loads((folder / "gold.json").read_text())
    rows = replay(binary, inputs, work, name)
    answers = {a["queryID"]: a for a in gold["answers"]}
    texts = {q["id"]: q["text"] for q in inputs["queries"]}
    passed, failures, positive, top3, empty_screen = 0, [], 0, 0, 0
    for qid, answer in answers.items():
        row = rows[qid]
        ok = success(row["action"], [i.lower() for i in row["ids"]], row["placeChoices"], answer)
        passed += ok
        if not ok:
            failures.append((texts[qid], answer["action"], row["action"], len(answer["ids"]), len(row["ids"])))
        if answer["action"] == "results":
            positive += 1
            shown = [i.lower() for i in row["ids"] + row["closeIDs"]]
            wanted = set(answer["acceptedTopIDs"] if answer["ordered"] else answer["ids"])
            top3 += bool(wanted & set(shown[:3]))
            empty_screen += not shown
    summary = {"passed": passed, "total": len(answers), "top3": top3, "positive": positive,
               "emptyScreens": empty_screen, "p95ms": percentile([r["ms"] for r in rows.values()], .95)}
    if name == "validation":
        observations = [dict(r, lane="rules", repeatIndex=0, modelAttempted=False, status="rules", localMs=r["ms"], finalMs=r["ms"]) for r in rows.values()]
        summary["recovery"] = len(answers) - len(check(inputs, gold, observations))
    return summary, failures


def percentile(values, p):
    values = sorted(values)
    return round(values[max(0, int(len(values) * p) - 1)], 3) if values else None


def year(binary, work, trial):
    fixtures = EVALUATION / "year-study/fixtures"
    histories, queries, keys, reverse = [], [], {}, {}
    for runner in [f"{n:02}" for n in range(1, 11)]:
        data, runner_keys, runner_reverse, _ = prepare(fixtures / f"{runner}.json", runner, trial)
        histories += data["histories"]
        queries += data["queries"]
        keys.update(runner_keys)
        reverse.update(runner_reverse)
        corpus = data
    corpus = dict(corpus, histories=histories, queries=queries)
    rows = replay(binary, corpus, work, f"year-{trial}")
    dates = {}
    for runner in [f"{n:02}" for n in range(1, 11)]:
        fixture = json.loads(gzip.decompress((fixtures / f"{runner}.json.gz").read_bytes()))
        dates.update({(runner, r["id"]): r["date"] for r in fixture["runs"]})
    outcomes, failures, top3, positive, empty_screen = Counter(), [], 0, 0, 0
    for qid, key in keys.items():
        runner = qid.split("-")[0]
        row = rows[qid]
        returned = [reverse[i.lower()] for i in row["ids"]]
        close = [reverse[i.lower()] for i in row["closeIDs"]]
        run_dates = {k[1]: date.fromisoformat(v) for k, v in dates.items() if k[0] == runner}
        cutoff = year_grader.FIRST_SUNDAY + timedelta(weeks=key["week"] - 1)
        result = year_grader.outcome(dict(returned=returned, action=row["action"], mode=key["mode"]),
                                     set(key["ids"]), run_dates, cutoff)
        outcomes[result] += 1
        if result != "correct":
            failures.append((key["text"], result, len(key["ids"]), len(returned), len(close)))
        if key["ids"]:
            positive += 1
            top3 += bool(set(key["ids"]) & set((returned + close)[:3]))
            empty_screen += not (returned or close)
    summary = {"correct": outcomes["correct"], "total": len(keys), "outcomes": dict(outcomes),
               "top3": top3, "positive": positive, "emptyScreens": empty_screen,
               "p95ms": percentile([r["ms"] for r in rows.values()], .95)}
    return summary, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trial", type=int, default=5, choices=range(1, 6))
    parser.add_argument("--failures", type=Path, help="Write every miss to this JSON file")
    parser.add_argument("--debug", help="Print the scores behind one query text")
    args = parser.parse_args()
    global ARGS
    ARGS = args
    if args.debug:
        os.environ["WR_DEBUG_TEXT"] = args.debug
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        binary = build(work)
        report, misses = {}, {}
        for name in ("development", "validation"):
            report[name], misses[name] = split(binary, work, name)
        report["year"], misses["year"] = year(binary, work, args.trial)
    print(json.dumps(report, indent=2))
    if args.failures:
        args.failures.write_text(json.dumps(misses, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
