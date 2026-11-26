"""Grade completed simulator searches against independent, frozen weekly answer keys."""

import argparse
from collections import Counter
from datetime import date, timedelta
import gzip
from hashlib import sha256
import json
from pathlib import Path


RUNNERS = range(1, 11)
WEEKS = set(range(1, 53))
FIRST_SUNDAY = date(2025, 1, 5)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def outcome(row, expected, run_dates, cutoff):
    returned = row["returned"]
    if any(item not in run_dates for item in returned):
        return "unknown_id"
    if any(run_dates[item] > cutoff for item in returned):
        return "future_workout"
    if len(set(returned)) != len(returned):
        return "duplicate_id"
    if row["action"] not in ("results", "empty"):
        return "other_action"
    if not expected:
        return "correct" if row["action"] == "empty" and not returned else "false_match"
    if not returned:
        return "false_empty"
    if row["action"] != "results":
        return "wrong_action"
    if row["mode"] == "first":
        return "correct" if returned[0] in expected else "wrong_first"
    missing = expected.difference(returned)
    extra = set(returned).difference(expected)
    if missing and extra:
        return "missing_and_extra"
    if missing:
        return "missing_only"
    return "extra_only" if extra else "correct"


def grade_runner(runner, args, checksums, counts, diagnostics):
    plain = args.runs / f"{runner}.json"
    source = plain.read_bytes() if plain.exists() else gzip.decompress((args.runs / f"{runner}.json.gz").read_bytes())
    digest = sha256(source).hexdigest()
    require(digest == checksums[runner], f"Runner {runner}: source differs from frozen manifest")
    fixture = json.loads(source)
    run_dates = {r["id"]: date.fromisoformat(r["date"]) for r in fixture["runs"]}
    require(len(run_dates) == len(fixture["runs"]), f"Runner {runner}: duplicate workout IDs")
    queries = fixture["trials"][args.trial - 1]
    keys = {q["text"]: q for q in queries}
    require(len(keys) == len(queries) == 120, f"Runner {runner}: expected 120 unique queries")
    require({q["week"] for q in queries} == WEEKS, f"Runner {runner}: incomplete calendar")
    answers = (args.output / runner / "answers.jsonl").read_text().splitlines()
    require(len(answers) == 120, f"Runner {runner}: expected 120 answers, got {len(answers)}")
    seen_ids, seen_texts = set(), set()
    per_runner = Counter()
    for line in answers:
        row = json.loads(line)
        label = f"Runner {runner}, query {row['id']}"
        text = row["text"]
        require(row["id"] not in seen_ids, f"{label}: duplicate observation ID")
        require(text in keys and text not in seen_texts, f"{label}: unknown or repeated query")
        seen_ids.add(row["id"])
        seen_texts.add(text)
        key = keys[text]
        mode, expected = key["mode"], set(key["ids"])
        require(mode in ("set", "first") and len(expected) == len(key["ids"]), f"{label}: invalid key")
        require(row["mode"] == mode and row["week"] == key["week"], f"{label}: mode or week mismatch")
        require(isinstance(row["expected"], list) and sorted(row["expected"]) == sorted(key["ids"]),
                f"{label}: submitted key differs from frozen key")
        require(isinstance(row["returned"], list) and all(isinstance(i, str) for i in row["returned"]),
                f"{label}: invalid returned IDs")
        cutoff = FIRST_SUNDAY + timedelta(weeks=key["week"] - 1)
        require(all(i in run_dates and run_dates[i] <= cutoff for i in expected), f"{label}: ineligible gold ID")
        result = outcome(row, expected, run_dates, cutoff)
        bucket = mode if expected else "empty"
        for scope in (counts, per_runner):
            scope["total"] += 1
            scope["correct"] += result == "correct"
            scope[bucket + "_total"] += 1
            scope[bucket + "_correct"] += result == "correct"
            scope["tied_first"] += mode == "first" and len(expected) > 1
        if result != "correct":
            diagnostics.append(dict(runner=runner, trial=args.trial, error=result, **{
                field: row[field] for field in ("id", "week", "text", "mode", "action", "expected", "returned")
            }))
    return dict(per_runner, errors=per_runner["total"] - per_runner["correct"],
                workouts=len(run_dates), frozen_sha256=digest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--trial", required=True, type=int, choices=range(1, 6))
    parser.add_argument("--runs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    manifest = Path(__file__).resolve().parent / "year-study" / "fixtures" / "manifest.json"
    checksums = {r["runner"]: r["sha256"] for r in json.loads(manifest.read_text())}
    counts, diagnostics = Counter(), []
    per_runner = {}
    for number in RUNNERS:
        runner = f"{number:02d}"
        per_runner[runner] = grade_runner(runner, args, checksums, counts, diagnostics)
    summary = dict(counts, trial=args.trial, errors=len(diagnostics),
                   accuracy=counts["correct"] / counts["total"],
                   error_kinds=Counter(item["error"] for item in diagnostics), per_runner=per_runner)
    (args.output / "diagnostics.jsonl").write_text("".join(json.dumps(d) + "\n" for d in diagnostics))
    (args.output / "score.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"Trial {args.trial}: {counts['correct']}/{counts['total']} ({summary['accuracy']:.2%})")


if __name__ == "__main__":
    main()
