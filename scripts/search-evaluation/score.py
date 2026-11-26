#!/usr/bin/env python3
"""Score synthetic observations independently of the model, parser and executor."""
import argparse
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
import json
from math import ceil
from pathlib import Path
import random
import statistics
import unicodedata

from run import REGRESSIONS, corpus_fingerprints, evaluator_fingerprint, is_regression_split, repeated_queries, write_json


def quantile(values, p):
    if not values:
        return None
    values = sorted(values)
    return round(values[max(0, ceil(len(values) * p) - 1)], 3)


def time_stats(values):
    return {"n": len(values), "p50": quantile(values, .50), "p95": quantile(values, .95)}


def words(text):
    return " ".join(unicodedata.normalize("NFKD", text.casefold()).replace(",", " ").split())


def normalized(key, value, aliases):
    if key in {"duration", "distance"}:
        try:
            op, n = value.split(":")
            return op + ":" + str(Decimal(n).quantize(Decimal(".00001")))
        except (ValueError, InvalidOperation):
            return value
    value = words(value)
    if key == "place":
        tokens = value.split()
        if tokens and tokens[-1] in aliases:
            return " ".join(tokens[:-1] + [aliases[tokens[-1]]])
    return value


def success(action, ids, choices, gold):
    expected = set(gold["ids"])
    if action != gold["action"]:
        return False
    if action == "clarify":
        return not ids and {words(c) for c in choices} == {words(c) for c in gold["placeChoices"]}
    if action == "empty":
        return not ids
    if gold["ordered"]:
        return bool(ids) and ids[0] in gold["acceptedTopIDs"]
    return set(ids) == expected


def score_row(raw, q, answer, aliases):
    ids = [s.lower() for s in raw["ids"]]
    expected_slots = {k: normalized(k, v, aliases) for k, v in answer["slots"].items()}
    observed_slots = {k: {normalized(k, v, aliases) for v in values} for k, values in raw["slots"].items()}
    if "sort" not in expected_slots and observed_slots.get("sort") == {"newest"}:
        del observed_slots["sort"]
    matched = {k for k, value in expected_slots.items() if value in observed_slots.get(k, set())}
    wrong_ids = {}
    for constraint in answer["constraints"]:
        errors = set(ids) - set(constraint["allowedIDs"])
        if errors:
            wrong_ids[constraint["slot"]] = sorted(errors)
    protected = q["boundary"] or q["exclusion"]
    if protected:
        for key in {"distance", "duration", "date", "excludingSport", "excludingType"} & expected_slots.keys():
            if observed_slots.get(key) != {expected_slots[key]}:
                matched.discard(key)
    # Empty results can conceal a discarded exclusion. Count both missing semantic constraints
    # and surviving out-of-bounds rows; no slots are available for the frozen legacy engine.
    dropped = sorted(set(expected_slots) - matched) if protected and raw["lane"] != "legacy" else []
    wanted = set(answer["ids"])
    shown = ids + [s.lower() for s in raw.get("closeIDs", [])]
    return {
        "queryID": q["id"], "family": q["family"], "category": q["category"],
        "conversational": q["conversational"], "protected": protected, "lane": raw["lane"],
        "action": raw["action"], "expectedAction": answer["action"], "attempted": raw["modelAttempted"],
        "status": raw["status"], "reason": raw.get("reason"), "success": success(raw["action"], ids, raw["placeChoices"], answer), "repeatIndex": raw["repeatIndex"],
        "reciprocalRank": next((1 / i for i, value in enumerate(ids, 1) if value in (answer["acceptedTopIDs"] or wanted)), 0)
                          if wanted else None,
        # Ranked search lists close matches after the best ones. Did the right workout make the first three?
        "topThree": bool(set(shown[:3]) & set(answer["acceptedTopIDs"] or wanted)) if wanted else None,
        "precision": len(set(ids) & wanted) / len(ids) if ids else None,
        "recall": len(set(ids) & wanted) / len(wanted) if wanted else None,
        "wrongIDsBySlot": wrong_ids, "droppedSlots": dropped,
        "slotTP": len(matched), "slotPredicted": sum(map(len, observed_slots.values())), "slotExpected": len(expected_slots),
        "localMs": raw["localMs"], "finalMs": raw["finalMs"],
        "prediction": (raw["action"], ids, raw["slots"], raw["additionalTerms"], sorted(raw["placeChoices"])),
    }


def macro(rows):
    by_category = defaultdict(list)
    for row in rows:
        by_category[row["category"]].append(row["success"])
    return statistics.mean(statistics.mean(values) for values in by_category.values()) if by_category else None


def summary(rows, lane):
    by_category = defaultdict(list)
    by_action = defaultdict(list)
    by_temperature = defaultdict(list)
    statuses = Counter()
    initial = [r for r in rows if r["repeatIndex"] == 0]
    for r in initial:
        by_category[r["category"]].append(r["success"])
        by_action[r["expectedAction"]].append(r["success"])
        statuses[r["status"]] += 1
    for i, row in enumerate(rows):
        by_temperature["first" if i == 0 else "subsequent"].append(row)
    model_rows = [r for r in rows if r["attempted"]]
    result = {
        "n": len(initial), "passed": sum(r["success"] for r in initial),
        "simple": {"n": sum(not r["conversational"] for r in initial),
                   "passed": sum(r["success"] for r in initial if not r["conversational"])},
        "conversational": {"n": sum(r["conversational"] for r in initial),
                           "passed": sum(r["success"] for r in initial if r["conversational"])},
        "macroSuccess": macro(initial), "byIntent": {k: {"n": len(v), "passed": sum(v)} for k, v in by_category.items()},
        "byExpectedAction": {k: {"n": len(v), "passed": sum(v)} for k, v in by_action.items()},
        "topThree": {"n": sum(r["topThree"] is not None for r in initial),
                     "passed": sum(bool(r["topThree"]) for r in initial)},
        "statuses": dict(statuses), "wrongConstraintResults": sum(bool(r["wrongIDsBySlot"]) for r in initial),
        "protectedViolations": (sum(r["protected"] and bool(r["droppedSlots"] or r["wrongIDsBySlot"]) for r in initial)
                                if lane != "legacy" else None),
        "protectedCases": sum(r["protected"] for r in initial),
        "latencyMs": {key: {field: time_stats([r[field] for r in group]) for field in ("localMs", "finalMs")}
                      for key, group in by_temperature.items()},
        "modelAttemptFinalMs": {"first": time_stats([r["finalMs"] for r in model_rows[:1]]),
                                "subsequent": time_stats([r["finalMs"] for r in model_rows[1:]])},
        "repeats": {"sets": 0, "exactOutputChanges": 0, "taskOutcomeChanges": 0},
    }
    for field in ("precision", "recall", "reciprocalRank"):
        values = [r[field] for r in initial if r[field] is not None]
        result[field] = statistics.mean(values) if values else None
    if lane != "legacy":
        tp = sum(r["slotTP"] for r in initial)
        denominator = sum(r["slotPredicted"] + r["slotExpected"] for r in initial)
        result["slotMicroF1"] = 2 * tp / denominator if denominator else None
    repeated = defaultdict(list)
    for row in rows:
        repeated[row["queryID"]].append(row)
    for group in repeated.values():
        if len(group) > 1:
            if sorted(r["repeatIndex"] for r in group) != [0, 1, 2]:
                raise ValueError("Incomplete repeat observations")
            result["repeats"]["sets"] += 1
            result["repeats"]["taskOutcomeChanges"] += int(len({(r["action"], r["success"]) for r in group}) > 1)
            result["repeats"]["exactOutputChanges"] += int(any(r["prediction"] != group[0]["prediction"] for r in group[1:]))
    return result


def compare(rows, left, right, conversational=False):
    by_id = defaultdict(dict)
    for row in rows:
        if row["repeatIndex"] == 0 and (not conversational or row["conversational"]):
            by_id[row["queryID"]][row["lane"]] = row
    pairs = [(r[left], r[right]) for r in by_id.values()]
    families = defaultdict(list)
    draws = []
    wins = losses = 0
    for first, second in pairs:
        delta = int(second["success"]) - int(first["success"])
        wins += delta > 0
        losses += delta < 0
        families[first["family"]].append(delta)
    groups = list(families.values())
    if not groups:
        return {"n": 0}
    # Resample independent scenario-family clusters, preserving all paired outcomes in each draw.
    rng = random.Random(32149)
    totals = [(sum(g), len(g)) for g in groups]
    for _ in range(5000):
        sample = rng.choices(totals, k=len(totals))
        draws.append(sum(n for n, _ in sample) / sum(k for _, k in sample))
    draws.sort()
    return {"n": len(pairs), "families": len(families), "wins": wins, "losses": losses, "ties": len(pairs)-wins-losses,
            "gain": (wins-losses)/len(pairs), "ci95": [draws[124], draws[4874]]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True, help="Output directory from run.py")
    parser.add_argument("--development-summary", type=Path, help="Passing development results required to issue a validation receipt")
    parser.add_argument("--prior-run", type=Path, help="Paired development comparison against earlier prompt on the identical corpus/device")
    args = parser.parse_args()
    manifest = json.loads((args.run / "manifest.json").read_text())
    data = json.loads(args.input.read_text())
    gold = json.loads((args.input.parent / "gold.json").read_text())
    payload = json.loads((args.run / "observations.json").read_text())
    if manifest["probe"] or manifest["corpusHashes"] != corpus_fingerprints(data["split"], args.input) or not data["split"] == gold["split"] == manifest["split"]:
        raise SystemExit("Cannot score a probe, changed corpus or mismatched split.")
    questions = {q["id"]: q for q in data["queries"]}
    answers = {a["queryID"]: a for a in gold["answers"]}
    aliases = {words(w["stateCode"]): words(w["stateName"]) for h in data["histories"] for w in h["workouts"] if w["stateCode"]}
    repeats_expected = {qid: [0, 1, 2] for qid in manifest["repeatIDs"]}
    samples = defaultdict(list)
    for row in payload["observations"]:
        samples[(row["lane"], row["queryID"])].append(row["repeatIndex"])
    if any(sorted(passes) != (repeats_expected.get(qid, [0]) if lane == "hybrid" else [0])
           for (lane, qid), passes in samples.items()):
        raise SystemExit("Mismatched repeat observations.")
    rows = [score_row(r, questions[r["queryID"]], answers[r["queryID"]], aliases) for r in payload["observations"]]
    lanes = manifest["lanes"]
    for lane in lanes:
        observed = [r["queryID"] for r in rows if r["lane"] == lane and r["repeatIndex"] == 0]
        if sorted(observed) != sorted(questions) or set(questions) != set(answers):
            raise ValueError("Incomplete primary lane or gold labels.")
    report = {**manifest, "evaluatorHash": evaluator_fingerprint(), "os": payload["os"], "hardware": payload["hardware"], "modelAvailability": payload["modelAvailability"],
              "promptVersion": payload.get("promptVersion"), "instructionHash": payload.get("instructionHash"),
              "lanes": {lane: summary([r for r in rows if r["lane"] == lane], lane) for lane in lanes},
              "eligible": False}
    for left, right in (("legacy", "rules"), ("rules", "hybrid")):
        if left in lanes and right in lanes:
            report[f"{right}Vs{left.title()}"] = compare(rows, left, right)
    if "hybrid" in lanes and "rules" in lanes:
        conv = compare(rows, "rules", "hybrid", True)
        report["conversationalHybridVsRules"] = conv
        suites = manifest.get("regressions", {})
        report["regressionsPassed"] = all(suite in suites and suites[suite] and
                                          all(r == "Passed" for r in suites[suite].values()) for suite in REGRESSIONS)
        if data["split"] == "development":
            required = set(repeated_queries(data["queries"]))
            repeats = defaultdict(list)
            for r in rows:
                if r["lane"] == "hybrid" and r["repeatIndex"] > 0:
                    repeats[r["queryID"]].append(r["repeatIndex"])
            report["repeatCoveragePassed"] = set(repeats) == required and all(sorted(v) == [1, 2] for v in repeats.values())
        hybrid = report["lanes"]["hybrid"]
        report["eligible"] = (report["regressionsPassed"] and report.get("repeatCoveragePassed", True) and hybrid["statuses"].get("model", 0) > 0
                              and hybrid["protectedViolations"] == 0 and conv.get("gain", 0) >= .05
                              and conv.get("ci95", [0])[0] > 0)
    if args.prior_run:
        if data["split"] != "development" or "hybrid" not in lanes:
            raise SystemExit("Prompt iteration comparisons use development hybrid observations.")
        previous = json.loads((args.prior_run / "manifest.json").read_text())
        previous_payload = json.loads((args.prior_run / "observations.json").read_text())
        if (any(previous[k] != manifest[k] for k in ("corpusHashes", "repeatIDs", "destination", "xcode"))
                or any(previous_payload[k] != payload[k] for k in ("os", "hardware", "locale"))):
            raise SystemExit("Different corpus, device, repeats, or system environment.")
        prior_observations = [score_row(r, questions[r["queryID"]], answers[r["queryID"]], aliases)
                              for r in previous_payload["observations"] if r["lane"] == "hybrid"]
        if sorted(r["queryID"] for r in prior_observations if r["repeatIndex"] == 0) != sorted(questions):
            raise SystemExit("The prior run is missing primary observations.")
        paired_rows = rows + [{**r, "lane": "prior"} for r in prior_observations]
        report["priorPromptComparison"] = {"promptVersion": previous_payload.get("promptVersion"),
                                           "fingerprint": previous["fingerprint"],
                                           "all": compare(paired_rows, "prior", "hybrid"),
                                           "conversational": compare(paired_rows, "prior", "hybrid", True)}
    if is_regression_split(data["split"]):
        report["eligible"] = False
        report["eligibilityReason"] = "Reviewed cases are regression evidence."
    if data["split"] == "validation" and report["eligible"]:
        development = json.loads(args.development_summary.read_text()) if args.development_summary else {}
        if development.get("eligible") and development.get("evaluatorHash") == report["evaluatorHash"] and development.get("binaryHash") == manifest["binaryHash"] and development.get("fingerprint") == manifest["fingerprint"] and development.get("split") == "development":
            write_json(args.run / "freeze.json", {"eligible": True, "evaluatorHash": report["evaluatorHash"], "fingerprint": manifest["fingerprint"], "binaryHash": manifest["binaryHash"]})
    write_json(args.run / "summary.json", report)
    if data["split"] == "development":
        # Examples are visible to prompt authors only on development.
        with (args.run / "diagnostics.jsonl").open("w") as stream:
            for row in rows:
                print(json.dumps({**row, "text": questions[row["queryID"]]["text"], "goldSlots": answers[row["queryID"]]["slots"]}), file=stream)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
