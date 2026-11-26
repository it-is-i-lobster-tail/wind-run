"""Compare the actual on-device search paths with frozen, synthetic workout histories."""
import argparse
from collections import Counter
from hashlib import sha256
import json
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from run import execute_cases


HERE = Path(__file__).resolve().parent / "tool-study"
FIXTURE_HASH = "491de44ba0a2f8ada5cadd79269e0746a105685491ad3a884da2a2083e29a128"


def corpus(replay, smoke=False, combined=False):
    raw = (HERE / "fixture.json").read_bytes()
    if sha256(raw).hexdigest() != FIXTURE_HASH:
        raise ValueError("The preregistered corpus changed")
    fixture = json.loads(raw)
    data = dict(now=fixture["asOf"], timeZone="UTC", firstWeekday=1, locale="en_US", histories=[], queries=[])
    keys = {}
    ids = {}
    for history, rows in fixture["histories"].items():
        workouts = []
        for code, day, city, state, km, minutes, profile, title, notes in rows:
            uid = str(uuid5(NAMESPACE_URL, f"wind-run/tool-study/{history}/{code}"))
            ids[history, code] = uid
            workouts.append(dict(id=uid, sport="running", kind="free", workoutType="free", startedAt=day + "T09:00:00Z",
                                 city=city, stateCode=state, countryCode="US", distanceMeters=km * 1000,
                                 activeSeconds=minutes * 60, elapsedSeconds=minutes * 60,
                                 profile=profile, title=title, notes=notes))
        data["histories"].append(dict(id=history, workouts=workouts))
    # Separate post-comparison smoke cases exercise a terrain tool call with minimal wording.
    questions = ([["coast", "terrain", "climbs", "c"], ["coast", "terrain", "descents", "b"]]
                 if smoke else fixture["questions"])
    if combined:
        questions = json.loads((HERE / "combined-filters.json").read_text())
    for i, (history, category, text, expected) in enumerate(questions):
        if replay and not smoke and i not in fixture["replayIndices"]:
            continue
        qid = f"S{i+1:02d}" if smoke else f"Q{i+1:02d}"
        data["queries"].append(dict(id=qid, historyID=history, text=text))
        keys[qid] = (category, [ids[history, char] for char in expected])
    return data, keys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=["comparison", "hybrid-replay", "fallback-replay", "keyword-smoke", "combined-filters"], required=True)
    parser.add_argument("--configuration", type=Path, required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data, keys = corpus(args.phase not in ("comparison", "combined-filters"), smoke=args.phase == "keyword-smoke",
                        combined=args.phase == "combined-filters")
    lanes = {"combined-filters": ["rulesOnly", "toolHybrid"], "comparison": ["rulesOnly", "hybrid", "toolHybrid"], "hybrid-replay": ["toolHybrid"],
             "fallback-replay": ["rulesOnly"], "keyword-smoke": ["toolHybrid", "rulesOnly"]}[args.phase]
    args.output.mkdir(parents=True, exist_ok=False)
    execute_cases(data, args.output, args.configuration, args.destination, lanes, [], {"fixtureHash": FIXTURE_HASH})
    payload = json.loads((args.output / "observations.json").read_text())
    rows = []
    for obs in payload["observations"]:
        cat, expected = keys[obs["queryID"]]
        found = [s.lower() for s in obs["ids"]]
        correct = (obs["action"] == ("results" if expected else "empty") and sorted(found) == sorted(expected))
        rows.append(dict(query=obs["queryID"], category=cat, lane=obs["lane"], expected=expected, returned=found,
                         correct=correct, action=obs["action"], status=obs["status"], reason=obs.get("reason"),
                         attempted=obs["modelAttempted"], calls=obs.get("toolCalls", 0), ms=round(obs["finalMs"], 2)))
    if Counter((r["query"], r["lane"]) for r in rows) != Counter((q, lane) for q in keys for lane in lanes):
        raise ValueError("Missing or duplicate observation")
    result = {"phase": args.phase, "fixtureHash": FIXTURE_HASH, "os": payload["os"], "hardware": payload["hardware"],
              "modelAvailability": payload["modelAvailability"], "rows": rows}
    (args.output / "scores.json").write_text(json.dumps(result, indent=2) + "\n")
    for lane in lanes:
        by_lane = [r for r in rows if r["lane"] == lane]
        print(lane, sum(r["correct"] for r in by_lane), "/", len(by_lane), "attempts", sum(r["attempted"] for r in by_lane),
              "calls", sum(r["calls"] for r in by_lane), Counter(r["status"] for r in by_lane))


if __name__ == "__main__":
    main()
