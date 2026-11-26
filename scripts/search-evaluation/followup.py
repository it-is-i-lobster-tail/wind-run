#!/usr/bin/env python3
"""Paired simulator research audit. V1 blind inputs and promotion receipts are never used."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from check_recovery import check as check_recovery
from run import HERE, REPO, digest, execute_cases, write_json
from score import compare, score_row, summary, words


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_inputs(path):
    dataset = read(path)
    split = dataset["split"]
    if split not in ("validation", "challenge"):
        raise ValueError("Research replay accepts retired v1 validation or the independently frozen challenge.")
    index = "v1-fingerprints.json" if split == "validation" else "v2-challenge-fingerprints.json"
    expected = read(HERE / "corpus" / index)[split]
    gold = path.parent / "gold.json"
    hashes = {"corpus": sha(path), "gold": sha(gold)}
    if any(expected[key] != value for key, value in hashes.items()):
        raise ValueError("Inputs differ from the custodian's frozen corpus or gold.")
    return dataset, hashes


def product_fingerprint():
    paths = sorted(p for folder in ("WindRun", "WindRunTests", "Shared") for p in (REPO / folder).rglob("*.swift"))
    return digest(paths)


def reference():
    return read(HERE / "benchmark-results.json")["developmentPromptV2"]


def replay(options):
    if options.lanes == "rules":
        lanes = ["rules"]
    elif options.lanes in ("rules,hybrid", "rules,hybrid,forcedModel") and options.role == "revised":
        lanes = options.lanes.split(",")
    else:
        raise ValueError("Use rules for prior. Revised runs support rules, rules,hybrid, or rules,hybrid,forcedModel.")
    dataset, hashes = checked_inputs(options.input)
    split = dataset["split"]
    if "forcedModel" in lanes and split != "challenge":
        raise ValueError("Forced interpretation is a fresh-challenge diagnostic only.")
    frozen = reference()
    source = frozen["fingerprint"] if options.role == "prior" else product_fingerprint()
    output = options.output.resolve()
    if split == "challenge" and (output.is_relative_to(REPO) or options.input.resolve().is_relative_to(REPO)):
        raise ValueError("Keep the fresh challenge and raw traces in the custodian's private workspace.")
    if split == "challenge" and options.role == "revised":
        if not options.candidate_receipt:
            raise ValueError("Freeze the candidate binary on the retired cohort before the challenge.")
        receipt = read(options.candidate_receipt)
        if (receipt.get("auditRole") != "revised" or receipt.get("split") != "validation"
                or receipt.get("fingerprint") != source or not receipt.get("regressions")
                or receipt.get("retiredRecovery") != {"passed": 90, "total": 90}):
            raise ValueError("Challenge requires a passing same-source retired-run receipt.")
        if not options.existing_build:
            raise ValueError("Challenge requires the exact binary frozen in the retired-run receipt.")
    elif options.candidate_receipt:
        raise ValueError("A candidate receipt is only used on the fresh challenge.")
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    derived = options.derived_data.resolve()
    product = derived / "Build/Products"
    provenance = derived / "search-evaluation-build.json"
    if options.role == "prior" and not options.existing_build and product_fingerprint() != source:
        raise ValueError("Rebuild prior rules only in an isolated checkout restored to the verified source receipt.")
    simulator = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
    if not any(d["udid"] == options.destination for runtime, devices in simulator["devices"].items()
               if ".iOS-" in runtime for d in devices):
        raise ValueError("Select an available iOS simulator.")
    if not options.existing_build:
        subprocess.run(["xcodebuild", "-quiet", "-jobs", "3", "-project", "WindRun.xcodeproj", "-scheme", "WindRun",
                        "-destination", f"id={options.destination}", "-derivedDataPath", derived, "build-for-testing"],
                       cwd=REPO, check=True)
    config, = product.glob("WindRun_*.xctestrun")
    bundle = product / "Debug-iphonesimulator/WindRun.app"
    binary = digest([bundle / "WindRun", bundle / "PlugIns/WindRunTests.xctest/WindRunTests", *bundle.glob("WindRun.debug.dylib")])
    stamp = {"fingerprint": source, "binaryHash": binary}
    if options.role == "prior":
        if binary != frozen["binaryHash"] and product_fingerprint() != frozen["fingerprint"]:
            raise ValueError("Neither an archived measured binary nor a verified prior-source rebuild.")
        if options.existing_build and read(provenance) != stamp:
            raise ValueError("Archived binary and build receipt differ.")
        if not options.existing_build:
            write_json(provenance, stamp)
    elif product_fingerprint() != source:
        raise ValueError("Source changed during preparation.")
    elif options.existing_build:
        if read(provenance) != stamp:
            raise ValueError("No matching build provenance. Build the candidate first.")
    else:
        write_json(provenance, stamp)
    if split == "challenge" and options.role == "revised" and receipt["binaryHash"] != binary:
        raise ValueError("Candidate binary changed after freeze.")
    manifest = {**stamp, "split": split, "researchAudit": True, "auditRole": options.role, "lanes": lanes,
                "probe": False, "repeatIDs": [], "corpusHashes": hashes, "destination": options.destination,
                "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip()}
    if options.role == "prior":
        manifest["priorBuild"] = "archived measured binary" if binary == frozen["binaryHash"] else "verified source rebuild"
    if options.candidate_receipt:
        manifest["retiredReceiptHash"] = sha(options.candidate_receipt)
    write_json(output / "manifest.json", manifest)
    execute_cases(dataset, output, config, options.destination, lanes, [], manifest)
    if split == "validation" and options.role == "revised":
        payload = read(output / "observations.json")
        failures = check_recovery(dataset, read(options.input.parent / "gold.json"), payload["observations"])
        total = len(dataset["queries"])
        recorded = read(output / "manifest.json")
        recorded["retiredRecovery"] = {"passed": total - len(failures), "total": total}
        write_json(output / "manifest.json", recorded)
        if failures:
            raise SystemExit(f"{len(failures)} retired recovery regressions; see check_recovery.py for details.")


def outcomes(raw, questions, gold, aliases, name):
    rows = []
    for r in raw:
        qid = r["queryID"]
        g = gold[qid]
        ids = [str(uid).lower() for uid in r["ids"]]
        expected = set(g["ids"])
        row = score_row({**r, "lane": name}, questions[qid], g, aliases)
        row.update(ids=ids, actualSet=set(ids), expectedSet=expected,
                   exact=row["success"] and set(ids) == expected,
                   wrongRows=len(set(ids) - expected),
                   predicateWrongRows=len(set().union(*row["wrongIDsBySlot"].values())))
        rows.append(row)
    if sorted(r["queryID"] for r in rows) != sorted(gold):
        raise ValueError(f"Incomplete primary results for {name}.")
    return rows


def count_slice(rows, prior):
    positives = [r for r in rows if r["expectedAction"] == "results"]
    misses = [r for r in rows if r["expectedAction"] == "results" and prior[r["queryID"]]["action"] == "empty"]
    controls = [r for r in rows if r["expectedAction"] != "results"]
    good_before = [r for r in rows if prior[r["queryID"]]["success"]]
    return {
        "expectedNonempty": len(positives),
        "incorrectEmpty": sum(r["action"] == "empty" for r in positives),
        "priorWrongEmpty": len(misses),
        "priorWrongEmptyNowNonempty": sum(bool(r["ids"]) for r in misses),
        "priorWrongEmptyNowTaskCorrect": sum(r["success"] for r in misses),
        "priorWrongEmptyNowExact": sum(r["exact"] for r in misses),
        "priorWrongEmptyWithWrongRows": sum(bool(r["wrongRows"]) for r in misses),
        "previouslyPassing": len(good_before), "previouslyPassingLost": sum(not r["success"] for r in good_before),
        "negativeControls": {action: {"total": sum(r["expectedAction"] == action for r in controls),
                                     "passed": sum(r["expectedAction"] == action and r["success"] for r in controls)}
                             for action in ("empty", "clarify")},
        "allUnexpectedWorkoutIDs": sum(r["wrongRows"] for r in rows),
        "queriesWithUnexpectedWorkoutIDs": sum(bool(r["wrongRows"]) for r in rows),
        "rowsViolatingExplicitPredicates": sum(r["predicateWrongRows"] for r in rows),
        "allExact": sum(r["exact"] for r in rows),
    }


def report(options):
    dataset, hashes = checked_inputs(options.input)
    split = dataset["split"]
    gold = {x["queryID"]: x for x in read(options.input.parent / "gold.json")["answers"]}
    questions = {q["id"]: q for q in dataset["queries"]}
    aliases = {words(w["stateCode"]): words(w["stateName"]) for h in dataset["histories"]
               for w in h["workouts"] if w["stateCode"]}
    before, after = (read(folder / "manifest.json") for folder in (options.prior, options.revised))
    previous, revised = (read(folder / "observations.json") for folder in (options.prior, options.revised))
    measured_prior = before["binaryHash"] == reference()["binaryHash"]
    rebuilt_prior = before.get("priorBuild") == "verified source rebuild" and before["fingerprint"] == reference()["fingerprint"]
    if (not (measured_prior or rebuilt_prior) or after.get("auditRole") != "revised"
            or any(m["corpusHashes"] != hashes or m["split"] != split for m in (before, after))
            or before["destination"] != after["destination"] or before["xcode"] != after["xcode"]
            or any(previous[k] != revised[k] for k in ("os", "hardware", "locale", "instructionHash"))):
        raise ValueError("Paired results require the measured baseline, same inputs, runtime, locale and prompt.")
    all_rows = []
    for payload, lane, name in [(previous, "rules", "priorRules"), (revised, "rules", "revisedRules"),
                                (revised, "hybrid", "revisedHybrid"), (revised, "forcedModel", "forcedModel")]:
        if payload is revised and lane not in after["lanes"]:
            continue
        observations = [r for r in payload["observations"] if r["lane"] == lane and r["repeatIndex"] == 0]
        all_rows.extend(outcomes(observations, questions, gold, aliases, name))
    by_lane = {name: [r for r in all_rows if r["lane"] == name] for name in dict.fromkeys(r["lane"] for r in all_rows)}
    prior = {r["queryID"]: r for r in by_lane["priorRules"]}
    result = {"split": split, "researchAudit": True, "corpusHashes": hashes,
              "priorBinary": before["binaryHash"], "priorBuild": "archived measured binary" if measured_prior else "verified source rebuild",
              "revisedBinary": after["binaryHash"],
              "revisedSource": after["fingerprint"], "instructionHash": revised["instructionHash"],
              "promptVersion": revised["promptVersion"], "simulatorOS": revised["os"], "simulatorHardware": revised["hardware"],
              "regressions": after["regressions"], "scorerHash": digest([Path(__file__), HERE / "score.py"]),
              "lanes": {}, "paired": {}}
    rules_by_id = {r["queryID"]: r for r in by_lane["revisedRules"]}
    for name, rows in by_lane.items():
        stats = summary(rows, name)
        stats.update(count_slice(rows, prior))
        stats["modelAttempted"] = sum(r["attempted"] for r in rows)
        if name in ("revisedHybrid", "forcedModel"):
            accepted = [r for r in rows if r["status"] == "model"]
            stats["acceptedInterpretations"] = len(accepted)
            stats["acceptedChangedResults"] = sum((r["action"], r["ids"]) !=
                                                  (rules_by_id[r["queryID"]]["action"], rules_by_id[r["queryID"]]["ids"])
                                                  for r in accepted)
            stats["acceptedImprovedTask"] = sum(r["success"] and not rules_by_id[r["queryID"]]["success"] for r in accepted)
            stats["acceptedHarmedTask"] = sum(not r["success"] and rules_by_id[r["queryID"]]["success"] for r in accepted)
        stats["modelRejectionReasons"] = dict(Counter(r["reason"] for r in rows if r["attempted"] and r["reason"]))
        result["lanes"][name] = stats
    for first, second in (("priorRules", "revisedRules"), ("revisedRules", "revisedHybrid"), ("priorRules", "revisedHybrid"),
                          ("revisedRules", "forcedModel"), ("revisedHybrid", "forcedModel")):
        if second in by_lane:
            result["paired"][f"{first}To{second}"] = {"all": compare(all_rows, first, second),
                                                      "conversational": compare(all_rows, first, second, True)}
    write_json(options.output, result)
    if options.development_diagnostics:
        if split != "validation":
            raise ValueError("Only retired cases can be shared with the implementer.")
        failures = [{"text": questions[r["queryID"]]["text"], "queryID": r["queryID"], "gold": gold[r["queryID"]]["slots"],
                     "priorEmpty": prior[r["queryID"]]["action"] == "empty", "action": r["action"],
                     "prediction": r["prediction"], "missingIDs": len(r["expectedSet"] - r["actualSet"]),
                     "unexpectedIDs": r["wrongRows"]} for r in by_lane["revisedRules"] if not r["exact"]]
        write_json(options.development_diagnostics, failures)
    for lane, stats in result["lanes"].items():
        print(f"{lane}: {stats['passed']}/{stats['n']} tasks; {stats['priorWrongEmptyNowExact']}/{stats['priorWrongEmpty']} exact prior empty recovery")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    cmds = parser.add_subparsers(dest="action", required=True)
    capture = cmds.add_parser("replay")
    for key in ("input", "output", "derived-data"):
        capture.add_argument("--" + key, type=Path, required=True)
    capture.add_argument("--destination", required=True)
    capture.add_argument("--role", choices=["prior", "revised"], required=True)
    capture.add_argument("--lanes", default="rules")
    capture.add_argument("--existing-build", action="store_true")
    capture.add_argument("--candidate-receipt", type=Path)
    score = cmds.add_parser("report")
    for key in ("input", "output", "prior", "revised"):
        score.add_argument("--" + key, type=Path, required=True)
    score.add_argument("--development-diagnostics", type=Path)
    options = parser.parse_args()
    if options.action == "replay":
        replay(options)
    else:
        report(options)


if __name__ == "__main__":
    main()
