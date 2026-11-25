#!/usr/bin/env python3
"""Rebuild private challenge inputs from independently authored examples and verify frozen hashes.

The private pack supplies every question, history row, expected result set, top-equivalence group
and clarification choice. SQLite also checks every answer against the annotated filters and facts.
"""
import argparse
import hashlib
import json
import os
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path
import uuid
from zoneinfo import ZoneInfo

from audit_corpus import audit, read_database, sql_predicate

BASE = Path(__file__).resolve().parent
MANIFEST = BASE / "corpus/v2-challenge-fingerprints.json"
NAMESPACE = uuid.UUID("8446757f-0a77-4b6a-b617-442af841e3c9")
ZONE = ZoneInfo("America/Chicago")


def identifier(text):
    return str(uuid.uuid5(NAMESPACE, text))


def serial(data):
    return (json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


def check(test, msg):
    if not test:
        raise ValueError(msg)


def decode_cases(path):
    inputs = dict(schemaVersion=1, split="challenge", now="2027-03-15T17:00:00Z", timeZone=ZONE.key,
                  locale="en_US", calendar="gregorian", firstWeekday=1, histories=[], queries=[])
    template_rows = []
    keys = set()
    questions = set()
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        if line.startswith("@"):
            family = line[1:]
            check(family not in keys, "Repeated family")
            keys.add(family)
            history = dict(id=identifier(family), workouts=[])
            inputs["histories"].append(history)
            by_alias = {}
            continue
        fields = line.split("|")
        if fields[0] == "w":
            _, alias, sport, kind, start, place, distance, seconds, paused, title, notes = fields
            city, state_code, state_name = place.split("~") if place else (None, None, None)
            when = datetime.fromisoformat(start).replace(tzinfo=ZONE).astimezone(timezone.utc)
            check(alias not in by_alias, f"Duplicate workout at line {line_no}")
            row = dict(id=identifier(family + "/" + alias), sport=sport, workoutType=kind,
                       kind=kind if kind in ("coached", "intervals") else "free",
                       startedAt=when.strftime("%Y-%m-%dT%H:%M:%SZ"), distanceMeters=float(distance),
                       activeSeconds=int(seconds), elapsedSeconds=int(seconds) + int(paused),
                       title=title, notes=notes, city=city, stateCode=state_code, stateName=state_name,
                       countryCode="US" if city else None)
            check(row["distanceMeters"] > 0 and row["activeSeconds"] > 0 and int(paused) >= 0, "Invalid workout")
            history["workouts"].append(row)
            by_alias[alias] = row
        else:
            _, style, category, annotations, result_labels, top_labels, choices, text = fields
            check(fields[0] == "q" and style in ("plain", "spoken"), f"Invalid question line {line_no}")
            check(category in ("lookup", "list", "ranked", "clarify"), f"Invalid category at line {line_no}")
            check(text.casefold() not in questions, "Repeated question")
            questions.add(text.casefold())
            slots = dict(entry.split("=", 1) for entry in annotations.split(";") if entry)
            q = dict(id=identifier(family + "/q/" + text), historyID=history["id"], family=family,
                     category=category, conversational=style == "spoken",
                     boundary=bool({"date", "distance", "duration"} & slots.keys()),
                     exclusion=bool({"excludingSport", "excludingType"} & slots.keys()), text=text)
            inputs["queries"].append(q)
            # Derive membership ONLY from the independent, explicitly assigned aliases here.
            selected = [by_alias[k] for k in result_labels.split(",") if k]
            sort = slots.get("sort", "newest")
            ordered = "sort" in slots
            selected.sort(key=lambda row: row["id"])
            if sort == "longest":
                selected.sort(key=lambda row: row["distanceMeters"], reverse=True)
            elif sort == "fastest":
                selected.sort(key=lambda row: Decimal(row["activeSeconds"]) / Decimal(str(row["distanceMeters"])))
            else:
                selected.sort(key=lambda row: row["startedAt"], reverse=sort == "newest")
            supplied_top = sorted(by_alias[k]["id"] for k in top_labels.split(",") if k)
            choices = sorted(choices.split("~")) if choices else []
            action = "clarify" if choices else ("results" if selected else "empty")
            check((category == "clarify") == bool(choices) and (not choices or not selected), f"Bad ambiguity at {line_no}")
            check(category != "lookup" or len(selected) <= 1, f"Invalid lookup at {line_no}")
            a = dict(queryID=q["id"], action=action, ids=[r["id"] for r in selected], ordered=ordered,
                     acceptedTopIDs=supplied_top, slots=slots, constraints=[], placeChoices=choices)
            template_rows.append((q, a))
    check(len(keys) == 12 and len(questions) == 72, "Expected 12 families and 72 queries")
    db = read_database(inputs)
    for q, a in template_rows:
        for slot, value in a["slots"].items():
            if slot != "sort":
                clause, params = sql_predicate(slot, value)
                rows = db.execute("SELECT id FROM workouts WHERE history = ? AND " + clause + " ORDER BY id",
                                  [q["historyID"], *params])
                a["constraints"].append(dict(slot=slot, allowedIDs=[r[0] for r in rows]))
    gold = dict(schemaVersion=1, split="challenge", answers=[a for _, a in template_rows])
    return inputs, gold


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--private-pack", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True, help="Fresh private directory for corpus.json and gold.json")
    p.add_argument("--freeze", action="store_true", help="Create the fingerprint manifest; refuses to overwrite any existing version")
    args = p.parse_args()
    root = BASE.parents[1]
    check(not any(p.resolve().is_relative_to(root) for p in (args.private_pack, args.output)),
          "Keep challenge inputs, outputs and gold outside the repository")
    inputs, gold = decode_cases(args.private_pack)
    counts = audit(inputs, gold)
    blobs = {"corpus": serial(inputs), "gold": serial(gold)}
    digests = {k: hashlib.sha256(v).hexdigest() for k, v in blobs.items()}
    digests["recipes"] = hashlib.sha256(args.private_pack.read_bytes()).hexdigest()
    manifest = {"challenge": digests}
    if args.freeze:
        with MANIFEST.open("x") as f:
            f.write(json.dumps(manifest, indent=2) + "\n")
    else:
        check(manifest == json.loads(MANIFEST.read_text()), "Frozen challenge fingerprints differ")
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    for name, blob in blobs.items():
        with os.fdopen(os.open(args.output / (name + ".json"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as stream:
            stream.write(blob)
    print(f"72 keys verified against independent SQL across 12 families: {dict(counts)}")


if __name__ == "__main__":
    main()
