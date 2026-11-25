"""Replay one frozen trial of weekly queries on ten assigned iOS simulators."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import UUID, uuid5

from run import execute_cases

NAMESPACE = UUID("81eb0eeb-0fdc-4fbf-9356-23f6261c1765")
SUNDAY = date(2025, 1, 5)
STATES = dict(zip("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY DC".split(),
                  "Alabama|Alaska|Arizona|Arkansas|California|Colorado|Connecticut|Delaware|Florida|Georgia|Hawaii|Idaho|Illinois|Indiana|Iowa|Kansas|Kentucky|Louisiana|Maine|Maryland|Massachusetts|Michigan|Minnesota|Mississippi|Missouri|Montana|Nebraska|Nevada|New Hampshire|New Jersey|New Mexico|New York|North Carolina|North Dakota|Ohio|Oklahoma|Oregon|Pennsylvania|Rhode Island|South Carolina|South Dakota|Tennessee|Texas|Utah|Vermont|Virginia|Washington|West Virginia|Wisconsin|Wyoming|District of Columbia".split("|")))


def prepare(path, runner, trial):
    raw = path.read_bytes() if path.exists() else gzip.decompress(path.with_suffix(".json.gz").read_bytes())
    source = json.loads(raw)
    workouts, reverse = [], {}
    state_codes = {v: k for k, v in STATES.items()}
    for r in source["runs"]:
        uid = str(uuid5(NAMESPACE, runner + "/" + r["id"]))
        reverse[uid] = r["id"]
        kind = r.get("workoutType", "free")
        workouts.append(dict(id=uid, sport="running", kind="intervals" if kind == "intervals" else "free",
                             workoutType=kind, startedAt=r["date"] + "T09:00:00Z", distanceMeters=r["km"]*1000,
                             activeSeconds=r["minutes"]*60, elapsedSeconds=r["minutes"]*60, title=r["title"],
                             notes=r["notes"], city=r["city"], stateCode=state_codes.get(r["state"], r["state"]),
                             countryCode="US", profile=r["profile"]))
    questions = source["trials"][trial-1]
    assert len(questions) == 120 and {q["week"] for q in questions} == set(range(1,53))
    keys, inputs = {}, []
    for i, q in enumerate(questions, 1):
        qid = f"{runner}-{i:03}"
        end = SUNDAY + timedelta(weeks=q["week"]-1)
        keys[qid] = q
        inputs.append(dict(id=qid, historyID=runner, text=q["text"], asOf=end.isoformat()+"T23:59:59Z"))
    data = dict(now="2025-12-31T12:00:00Z", timeZone="UTC", locale="en_US", firstWeekday=1,
                histories=[dict(id=runner, workouts=workouts)], queries=inputs)
    return data, keys, reverse, hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for opt in ("runs", "output", "configuration", "assignments"):
        p.add_argument("--"+opt, required=True, type=Path)
    p.add_argument("--trial", required=True, type=int, choices=range(1,6))
    p.add_argument("--workers", type=int, default=2)
    p.add_argument("--shutdown", action="store_true", help="Shut down the dedicated study devices after use")
    args = p.parse_args()
    sims = json.loads(args.assignments.read_text())
    assert len(sims) == len(set(sims.values())) == 10
    args.output.mkdir(parents=True, exist_ok=True)
    app = args.configuration.parent / "Debug-iphonesimulator/WindRun.app/WindRun.debug.dylib"
    build_hash = hashlib.sha256(app.read_bytes()).hexdigest()

    def replay(item):
        runner, sim = item
        data, keys, reverse, digest = prepare(args.runs / (runner+".json"), runner, args.trial)
        runner_dir = args.output / runner
        runner_dir.mkdir(exist_ok=True)
        manifest = dict(runner=runner, simulator=sim, trial=args.trial, historySHA256=digest, binarySHA256=build_hash)
        answers = runner_dir / "answers.jsonl"
        if answers.exists():
            receipt = json.loads((runner_dir / "receipt.json").read_text())
            if receipt != manifest:
                raise ValueError("Cannot reuse a result from another input or build.")
            return
        # A retry gets its own result bundle; completed peers keep their verified observations.
        attempt = runner_dir / ("attempt-"+str(1+len(list(runner_dir.glob("attempt-*")))))
        attempt.mkdir()
        print("Starting", runner, sim, flush=True)
        try:
            execute_cases(data, attempt, args.configuration, sim, ["rules"], [], dict(manifest))
            rows = json.loads((attempt/"observations.json").read_text())["observations"]
            assert len(rows) == len(keys) and {r["queryID"] for r in rows} == keys.keys()
            lines = []
            for row in rows:
                qid = row["queryID"]
                q = keys[qid]
                lines.append(json.dumps(dict(id=qid, week=q["week"], text=q["text"], mode=q["mode"],
                                             expected=q["ids"], returned=[reverse[s.lower()] for s in row["ids"]],
                                             action=row["action"]),ensure_ascii=False))
            (runner_dir/"receipt.json").write_text(json.dumps(manifest,indent=2))
            tmp = answers.with_suffix(".tmp")
            tmp.write_text("\n".join(lines)+"\n")
            tmp.replace(answers)
            print("Finished", runner, flush=True)
        finally:
            if args.shutdown:
                subprocess.run(["xcrun","simctl","shutdown",sim],check=False)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(replay, sorted(sims.items())))


if __name__ == "__main__":
    main()
