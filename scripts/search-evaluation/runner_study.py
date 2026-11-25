"""Replay the ten fictional runner histories on the shipping rules using the app test host."""
import argparse
import json
from pathlib import Path
from uuid import NAMESPACE_URL, uuid5

from run import execute_cases

HERE = Path(__file__).resolve().parent / "runners"


def corpus(terrain_controls=False):
    data = {"now": "2025-12-01T12:00:00Z", "timeZone": "UTC", "locale": "en_US",
            "firstWeekday": 1, "histories": [], "queries": []}
    keys = {}
    for index in range(1, 11):
        runner = f"{index:02d}"
        fixture = json.loads((HERE / "histories" / f"{runner}.json").read_text())
        runs, questions = fixture["runs"], fixture["questions"]
        if (len(questions) != 50 or len({q["text"] for q in questions}) != 50 or
                {r["date"][:7] for r in runs} != {f"2025-{month:02d}" for month in range(6, 12)}):
            raise ValueError(f"Incomplete history or questions for runner {runner}")
        workouts = []
        by_id = {}
        for r in runs:
            uid = str(uuid5(NAMESPACE_URL, f"wind-run/study/{runner}/{r['id']}"))
            if r["id"] in by_id or not (r["km"] > 0 and r["minutes"] > 0):
                raise ValueError(f"Invalid workout for runner {runner}")
            by_id[r["id"]] = uid
            kind = r.get("workoutType", "free")
            workouts.append(dict(id=uid, sport="running", kind="intervals" if kind == "intervals" else "free",
                                 workoutType=kind, startedAt=r["date"] + "T09:00:00Z",
                                 distanceMeters=r["km"] * 1000, activeSeconds=r["minutes"] * 60,
                                 elapsedSeconds=r["minutes"] * 60, city=r["city"], stateCode=r["state"],
                                 countryCode="US", title=r["title"], notes=r["notes"], profile=r["profile"]))
        data["histories"].append(dict(id=runner, workouts=workouts))
        if terrain_controls:
            profiles = {"hills": {"climb", "descent", "outBack"}, "uphill": {"climb", "outBack"},
                        "downhill": {"descent", "outBack"}}
            questions = [dict(text=text, mode="set", ids=[r["id"] for r in runs if r["profile"] in shapes])
                         for text, shapes in profiles.items()]
        reverse = {uid: name for name, uid in by_id.items()}
        for n, q in enumerate(questions, 1):
            qid = f"{runner}-{n:02d}"
            if not set(q["ids"]) <= by_id.keys() or q["mode"] not in ("set", "first"):
                raise ValueError(f"Invalid answer for {qid}")
            keys[qid] = (q, reverse)
            data["queries"].append(dict(id=qid, historyID=runner, text=q["text"]))
    return data, keys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", type=Path, required=True, help="Built WindRun .xctestrun")
    parser.add_argument("--destination", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--terrain-controls", action="store_true", help="Run the three literal grade controls per runner")
    args = parser.parse_args()
    data, keys = corpus(terrain_controls=args.terrain_controls)
    args.output.mkdir(parents=True, exist_ok=False)
    execute_cases(data, args.output, args.configuration, args.destination, ["rules"], [], {})
    observations = json.loads((args.output / "observations.json").read_text())["observations"]
    rows = []
    for obs in observations:
        qid = obs["queryID"]
        question, reverse = keys[qid]
        ids = [reverse[uid.lower()] for uid in obs["ids"]]
        rows.append(dict(id=qid, text=question["text"], mode=question["mode"], expected=question["ids"],
                         returned=ids, action=obs["action"], placeChoices=obs["placeChoices"]))
    if len(rows) != len(keys) or {r["id"] for r in rows} != keys.keys():
        raise ValueError("Incomplete or duplicated results")
    (args.output / "answers.jsonl").write_text("".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows))


if __name__ == "__main__":
    main()
