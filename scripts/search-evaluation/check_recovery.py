#!/usr/bin/env python3
"""Verify the public workout recovery regression suite against its frozen answers."""
import argparse
import json
from pathlib import Path

from run import corpus_fingerprints
from score import score_row, words


def check(inputs, gold, observations):
    queries = {q["id"]: q for q in inputs["queries"]}
    aliases = {words(w["stateCode"]): words(w["stateName"]) for h in inputs["histories"]
               for w in h["workouts"] if w["stateCode"]}
    answers = {a["queryID"]: a for a in gold["answers"]}
    rows = [r for r in observations if r["lane"] == "rules" and r["repeatIndex"] == 0]
    if len(rows) != len(queries) or {r["queryID"] for r in rows} != queries.keys() or queries.keys() != answers.keys():
        raise ValueError("Expected one rules result and one answer for every recovery query.")
    failures = []
    for row in rows:
        answer = answers[row["queryID"]]
        ids = [s.lower() for s in row["ids"]]
        query = queries[row["queryID"]]
        scored = score_row(row, query, answer, aliases)
        # Also preserve the full list of eligible workouts underneath a ranked first hit.
        exact = len(ids) == len(set(ids)) and set(ids) == set(answer["ids"])
        # All 90 frozen queries are fully described by their annotated slots.
        # A stray keyword or invented place can be invisible on an empty history.
        slots_match = scored["slotTP"] == scored["slotExpected"] == scored["slotPredicted"]
        if not (scored["success"] and exact and slots_match) or row["additionalTerms"]:
            failures.append(query["text"])
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--run", required=True, type=Path)
    args = parser.parse_args()
    corpus_fingerprints("validation", args.input)
    inputs = json.loads(args.input.read_text())
    gold = json.loads((args.input.parent / "gold.json").read_text())
    observations = json.loads((args.run / "observations.json").read_text())["observations"]
    failures = check(inputs, gold, observations)
    count = len(inputs["queries"])
    print(f"Workout recovery regressions: {count - len(failures)}/{count} correct")
    if failures:
        raise SystemExit("\n".join(f"  Failed: {query}" for query in failures))


if __name__ == "__main__":
    main()
