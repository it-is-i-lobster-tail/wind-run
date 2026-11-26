#!/usr/bin/env python3
"""Build reproducible synthetic workout-search inputs and separate, independently derived gold.

Only the Python standard library is needed. Use --help for export and verify options.
"""
import argparse
import csv
import hashlib
import json
import os
import re
import random
import uuid
from datetime import date, datetime, time, timedelta, timezone
from decimal import Decimal
from difflib import SequenceMatcher
from pathlib import Path
from tempfile import NamedTemporaryFile
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parent
NOW = datetime(2026, 11, 25, 12, tzinfo=ZoneInfo("America/Los_Angeles"))
MILE = Decimal("1609.344")
NAMESPACE = uuid.UUID("68ebbc23-19c3-4a05-91eb-ee98ba4d2e8b")
VERSION = 1
FAMILY_COUNT = {"development": 18, "validation": 9, "holdout": 9}
SPORTS = {"running": ("runs", "run"), "cycling": ("rides", "ride"), "hiking": ("hikes", "hike")}
PLACES = [
    ("Sacramento", "CA", "California"), ("Lafayette", "IN", "Indiana"),
    ("Flagstaff", "AZ", "Arizona"), ("Milwaukee", "WI", "Wisconsin"),
    ("Tacoma", "WA", "Washington"), ("Duluth", "MN", "Minnesota"),
    ("Boulder", "CO", "Colorado"), ("Burlington", "VT", "Vermont"),
    ("Richmond", "VA", "Virginia"), ("Boise", "ID", "Idaho"),
    ("Honolulu", "HI", "Hawaii"), ("Santa Fe", "NM", "New Mexico"),
]
TWINS = [
    (("Portland", "ME", "Maine"), ("Portland", "OR", "Oregon")),
    (("Salem", "OR", "Oregon"), ("Salem", "MA", "Massachusetts")),
    (("Springfield", "IL", "Illinois"), ("Springfield", "MO", "Missouri")),
    (("Jackson", "WY", "Wyoming"), ("Jackson", "MS", "Mississippi")),
]
TITLES = ["Cedar Loop", "Creek Ladder", "Beacon Outing", "Ridge Circuit", "Lake Steps",
          "Stone Bridge", "Valley Loop", "North Fork", "Harbor Laps", "Meadow Return"]
NOTE_WORDS = ["windy", "blisters", "wildflowers", "muddy", "rain", "knee", "snow", "sunrise"]
TYPES = ("free", "intervals", "distance", "time", "coached")
PERIODS = {
    "lastMonth": ("2026-10-01", "2026-11-01"), "thisMonth": ("2026-11-01", "2026-12-01"),
    "lastWeek": ("2026-11-15", "2026-11-22"), "thisWeek": ("2026-11-22", "2026-11-29"),
    "yesterday": ("2026-11-24", "2026-11-25"), "today": ("2026-11-25", "2026-11-26"),
}
OP = {"gt": "greater", "ge": "atLeast", "lt": "less", "le": "atMost", "eq": "equal"}
SPLIT_OFFSET = {"development": 0, "validation": 18, "holdout": 27}


def uid(key):
    return str(uuid.uuid5(NAMESPACE, key))


def seed_for(key):
    return int.from_bytes(hashlib.sha256(key.encode("utf-8")).digest()[:8], "big")


def timestamp(day, hour=8, minute=0):
    local = datetime.combine(day, time(hour, minute), tzinfo=NOW.tzinfo)
    return local.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def number_text(value):
    return format(Decimal(str(value)).normalize(), "f")


def load_recipes(path):
    families = {}
    family = None
    for line_no, line in enumerate(path.read_text().splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        if line.startswith("@"):
            family = line[1:]
            if not family or family in families:
                raise ValueError(f"{path}:{line_no}: duplicate/empty scenario")
            families[family] = []
        else:
            fields = next(csv.reader([line], delimiter="|"))
            if not family or len(fields) != 2:
                raise ValueError(f"{path}:{line_no}: expected intent|query")
            families[family].append((fields[0].split(), fields[1]))
    if any(len(queries) != 5 for queries in families.values()):
        raise ValueError("Each family has five query templates, instantiated against two different facts.")
    return families


def contexts(split, familyno, family):
    # Variation of clubs, activities, vocabulary and clocks of workouts is chosen before any query evaluation.
    rng = random.Random(seed_for(f"{split}/{family}"))
    index = SPLIT_OFFSET[split] + familyno
    spots = rng.sample(PLACES, 2)
    if split == "development" and familyno in (0, 1, 2):
        spots = PLACES[:2]
    twins = TWINS[(familyno + {"development": 0, "validation": 1, "holdout": 2}[split]) % len(TWINS)]
    if split == "development" and family == "cross-state-namesakes":
        twins = TWINS[0]
    sports = rng.sample(list(SPORTS), 2)
    if split == "development" and familyno in (0, 1):
        sports = ["cycling", "running"]
    contexts = []
    for variant in range(2):
        sport = sports[variant]
        spot = spots[variant]
        twin = twins[variant]
        mileage = {"cycling": [5, 10, 15, 20, 25], "running": [3, 5, 8, 10, 13], "hiking": [1, 2, 3, 5, 6]}
        mi = mileage[sport][(index + variant) % 5]
        if split == "development" and familyno == 0 and variant == 0:
            mi = 20
        contexts.append(dict(
            sport=sport, sports=SPORTS[sport][0], singular=SPORTS[sport][1],
            type=["intervals", "coached"][variant], types=["interval workouts", "coached workouts"][variant],
            city=spot[0], abbr=spot[1], state=spot[2], spot=spot,
            twin=twin[0], twinabbr=twin[1], twinstate=twin[2], twinspot=twin,
            title=TITLES[(index + 3 * variant) % len(TITLES)],
            note=NOTE_WORDS[(index + 2 * variant) % len(NOTE_WORDS)],
            mi=mi, km=[3, 5, 8, 10, 12][(index + 2 * variant) % 5],
            minutes=[20, 30, 45, 60][(index + variant) % 4],
            hours=[1, 2][variant],
        ))
    return contexts


def history(split, family, cx):
    key = f"{split}/{family}"
    rng = random.Random(seed_for(key))
    rows = []

    def add(c, when, distance, duration, *, sport=None, kind="free", location=None, note="", title="", pause=0):
        city, state_code, state_name = location or (None, None, None)
        rows.append(dict(id=uid(f"{key}/workout/{len(rows)}"), sport=sport or c["sport"],
                         workoutType=kind, kind=kind if kind in ("intervals", "coached") else "free",
                         startedAt=when, distanceMeters=float(distance), activeSeconds=duration,
                         elapsedSeconds=duration + pause, title=title, notes=note, city=city,
                         stateCode=state_code, stateName=state_name, countryCode="US" if city else None))

    for c in cx:
        # Representative synthetic speeds in meters/second. Independent boundary workouts avoid
        # teaching the benchmark that distance and active time thresholds always co-occur.
        speed = {"running": 2.8, "cycling": 6.0, "hiking": 1.2}[c["sport"]]
        # The exact threshold and its near neighbors make strict and inclusive comparisons observable.
        for delta in (-1, 0, 1):
            for km in (True, False):
                target = Decimal(1000) * c["km"] if km else MILE * c["mi"]
                add(c, timestamp(date(2026, 11, 21 + delta), 9 if km else 10), target + delta,
                    round(float(target) / speed), location=c["spot"], kind=c["type"] if km else "free",
                    pause=900 if delta <= 0 else 0)
            add(c, timestamp(date(2026, 11, 18 + delta), 9), round(c["minutes"] * 60 * speed),
                c["minutes"] * 60 + delta, location=c["spot"], kind=c["type"], pause=1200)
            add(c, timestamp(date(2026, 11, 23 + delta), 9), round(c["hours"] * 3600 * speed), c["hours"] * 3600 + delta,
                location=c["twinspot"], kind="intervals", pause=1200)
        for day, hour, minute in [(date(2026, 9, 30), 23, 59), (date(2026, 10, 1), 0, 0),
                                  (date(2026, 10, 31), 23, 59), (date(2026, 11, 1), 0, 0),
                                  (date(2026, 11, 15), 0, 0), (date(2026, 11, 22), 0, 0),
                                  (date(2026, 11, 24), 20, 30), (date(2026, 11, 25), 6, 15)]:
            add(c, timestamp(day, hour, minute), rng.randrange(2000, 11000), rng.randrange(1200, 4800),
                location=c["spot"], kind=rng.choice(TYPES), note="Felt " + c["note"])
        add(c, timestamp(date(2026, 10, 15), 12), 5600, 1950, location=c["spot"], title=c["title"],
            kind="intervals", note=c["note"])
        # Words occur in the wrong fields. Only recorded start locations satisfy a place filter.
        add(c, timestamp(date(2026, 11, 24), 7), 3500, 1450, location=None, note=f'{c["abbr"]} {c["state"]}')
        add(c, timestamp(date(2026, 11, 24), 6), 2500, 1450, location=c["twinspot"], title=c["note"],
            note=f'Next trip: {c["state"]} and {c["title"]}')
        # Exact ranking ties on distinct days in the requested geography and outside it.
        for day in (date(2026, 10, 12), date(2026, 10, 20)):
            long_distance, active = {"running": (30000, 7000), "cycling": (75000, 7900), "hiking": (20000, 12000)}[c["sport"]]
            add(c, timestamp(day, 10), long_distance, active, location=c["spot"], kind="free", note=c["note"])
        for _ in range(rng.randrange(5, 20)):
            day = date(2026, 9, 1) + timedelta(days=rng.randrange(84))
            spot = rng.choice([c["spot"], c["twinspot"], None])
            add(c, timestamp(day, rng.randrange(5, 22), rng.randrange(60)), rng.randrange(900, 9000),
                rng.randrange(1000, 4500), sport=rng.choice(list(SPORTS)), kind=rng.choice(TYPES),
                location=spot, note=rng.choice(["", "clear", "easy", c["note"]]), pause=rng.randrange(300))
    rng.shuffle(rows)
    return {"id": uid(key + "/history"), "workouts": rows}


def search_spec(tokens, c):
    """Render hand-authored semantic labels. This never reads or parses the user's query."""
    slots = {}
    empty, lookup, force_empty = False, False, False
    for token in tokens:
        if token == "blank":
            empty = True
        elif token == "lookup":
            lookup = True
        elif token == "noMatch":
            force_empty = True
        elif token in ("sport", "noSport", "type", "noType"):
            field, value = {"sport": ("sport", c["sport"]), "noSport": ("excludingSport", c["sport"]),
                            "type": ("type", c["type"]), "noType": ("excludingType", c["type"])}[token]
            slots[field] = value
        elif token in ("intervals", "noIntervals", "coached", "noCoached"):
            positive = token in ("intervals", "coached")
            slots["type" if positive else "excludingType"] = token.lower().removeprefix("no")
        elif token in ("state", "abbr", "city", "twin", "qualified"):
            place = {"state": c["state"], "abbr": c["state"], "city": c["city"], "twin": c["twin"],
                     "qualified": c["twin"] + ", " + c["twinabbr"]}[token]
            slots["place"] = place.lower()
        elif token in ("title", "note"):
            slots["title" if token == "title" else "notes"] = c[token].lower()
        elif token in PERIODS:
            slots["date"] = "/".join(PERIODS[token])
        elif token in ("longest", "fastest", "oldest", "newest"):
            slots["sort"] = token
        else:
            op, unit = token[:2], token[2:]
            multiplier, key, field = {"mi": (MILE, "mi", "distance"), "km": (1000, "km", "distance"),
                                      "min": (60, "minutes", "duration"), "hr": (3600, "hours", "duration")}[unit]
            slots[field] = OP[op] + ":" + number_text(multiplier * c[key])
    return slots, empty, lookup, force_empty


def comparison(actual, clause):
    op, raw = clause.split(":")
    target = Decimal(raw)
    actual = Decimal(str(actual))
    return {"greater": actual > target, "atLeast": actual >= target, "less": actual < target,
            "atMost": actual <= target, "equal": actual == target}[op]


def matches(row, slot, value):
    if slot in ("sport", "excludingSport", "type", "excludingType"):
        actual = row["sport"] if slot in ("sport", "excludingSport") else row["workoutType"]
        return (actual != value) if slot.startswith("excluding") else (actual == value)
    if slot == "date":
        lo, hi = value.split("/")
        local_day = datetime.fromisoformat(row["startedAt"].replace("Z", "+00:00")).astimezone(NOW.tzinfo).date()
        return date.fromisoformat(lo) <= local_day < date.fromisoformat(hi)
    if slot == "place":
        if row["city"] is None:
            return False
        forms = [row["city"], row["stateCode"], row["stateName"], row["city"] + ", " + row["stateCode"]]
        return value in (place.lower() for place in forms)
    if slot in ("title", "notes"):
        return value in row[slot].lower()
    return comparison(row["distanceMeters" if slot == "distance" else "activeSeconds"], value)


def expected(history_rows, slots, lookup):
    constraints = []
    for slot, value in slots.items():
        if slot != "sort":
            constraints.append({"slot": slot, "allowedIDs": sorted(r["id"] for r in history_rows if matches(r, slot, value))})
    place = slots.get("place")
    choices = sorted({r["city"] + ", " + r["stateCode"] for r in history_rows
                      if r["city"] and r["city"].lower() == place})
    ambiguous = len(choices) > 1
    eligible = {r["id"] for r in history_rows}.intersection(*(set(x["allowedIDs"]) for x in constraints))
    rows = [r for r in history_rows if r["id"] in eligible]
    sort = slots.get("sort", "newest")

    def rank(row):
        if sort == "fastest":
            return Decimal(str(row["activeSeconds"])) / Decimal(str(row["distanceMeters"]))
        if sort == "longest":
            return -Decimal(str(row["distanceMeters"]))
        seconds = datetime.fromisoformat(row["startedAt"].replace("Z", "+00:00")).timestamp()
        return seconds if sort == "oldest" else -seconds

    rows.sort(key=lambda r: (rank(r), r["id"]))
    if ambiguous:
        rows = []
    ordered = "sort" in slots
    category = "clarify" if ambiguous else ("ranked" if ordered else ("lookup" if lookup else "list"))
    return category, dict(action="clarify" if ambiguous else ("results" if rows else "empty"),
                          ids=[r["id"] for r in rows], ordered=ordered,
                          acceptedTopIDs=[r["id"] for r in rows if rank(r) == rank(rows[0])] if rows and ordered else [],
                          slots=slots, constraints=constraints, placeChoices=choices if ambiguous else [])


def make(split, pack):
    recipes = load_recipes(pack)
    if len(recipes) != FAMILY_COUNT[split]:
        raise ValueError(f"Wrong family count for {split}")
    inputs = dict(schemaVersion=VERSION, split=split, now=NOW.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                  timeZone=NOW.tzinfo.key, locale="en_US", calendar="gregorian", firstWeekday=1, histories=[], queries=[])
    answers = []
    for n, (family, cases) in enumerate(recipes.items()):
        cx = contexts(split, n, family)
        hist = history(split, family, cx)
        blank = {"id": uid(f"{split}/{family}/empty"), "workouts": []}
        inputs["histories"].append(hist)
        for i, (tokens, template) in enumerate(cases):
            style, *tokens = tokens
            if style not in ("plain", "spoken"):
                raise ValueError(f"{family}: assign a query style before evaluation")
            for v, c in enumerate(cx):
                slots, empty, lookup, force_empty = search_spec(tokens, c)
                data = blank if empty else hist
                if empty and blank not in inputs["histories"]:
                    inputs["histories"].append(blank)
                category, gold = expected(data["workouts"], slots, lookup)
                if force_empty and gold["action"] != "empty":
                    raise ValueError(f"{family}/{i} should return no results")
                if lookup and (gold["action"] != "results" or len(gold["ids"]) != 1):
                    raise ValueError(f"{family}/{i} should have a unique target")
                qid = uid(f"{split}/{family}/query/{i}/{v}")
                inputs["queries"].append(dict(id=qid, family=family, historyID=data["id"], category=category,
                                               conversational=style == "spoken",
                                               boundary=bool({"date", "distance", "duration"} & slots.keys()),
                                               exclusion=bool({"excludingSport", "excludingType"} & slots.keys()),
                                               text=template.format_map(c)))
                answers.append(dict(queryID=qid, **gold))
    check(inputs, answers)
    return inputs, dict(schemaVersion=VERSION, split=split, answers=answers)


def check(inputs, answers):
    histories = {h["id"]: h["workouts"] for h in inputs["histories"]}
    queries = inputs["queries"]
    if len(histories) != len(inputs["histories"]) or len(queries) != len(answers):
        raise ValueError("Duplicate history or missing answers")
    if len({q["id"] for q in queries}) != len(queries) or len({q["text"].casefold() for q in queries}) != len(queries):
        raise ValueError("Duplicate query ID or repeated wording within split")
    if len(queries) != FAMILY_COUNT[inputs["split"]] * 10:
        raise ValueError("Wrong split size")
    for q, a in zip(queries, answers):
        ids = {row["id"] for row in histories[q["historyID"]]}
        expected_set = set(a["ids"])
        if q["id"] != a["queryID"] or not expected_set <= ids or len(expected_set) != len(a["ids"]):
            raise ValueError("Invalid answer references")
        eligible = ids.intersection(*(set(x["allowedIDs"]) for x in a["constraints"]))
        if a["action"] != "clarify" and eligible != expected_set:
            raise ValueError("Inconsistent constraint truth sets")
        if not set(a["acceptedTopIDs"]) <= expected_set:
            raise ValueError("Invalid first-place equivalence")
        if (a["action"] == "results") != bool(a["ids"]):
            raise ValueError("Conflicting action/IDs")


def bytes_for(data):
    return (json.dumps(data, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def verify_fingerprint(split, pack, inputs, gold):
    fingerprints = json.loads((ROOT / "corpus" / "v1-fingerprints.json").read_text())
    actual = {"recipes": pack.read_bytes(), "corpus": bytes_for(inputs), "gold": bytes_for(gold)}
    if any(hashlib.sha256(blob).hexdigest() != fingerprints[split][key] for key, blob in actual.items()):
        raise ValueError(f"{split} differs from the frozen v1 corpus. Review changes under a new benchmark version.")


def write_json(path, data):
    # New files are owner-only even if an evaluator chooses a shared temporary directory.
    with NamedTemporaryFile(dir=path.parent, delete=False) as temp:
        temp.write(bytes_for(data))
    os.replace(temp.name, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    ex = sub.add_parser("export")
    ex.add_argument("--split", choices=FAMILY_COUNT, required=True)
    ex.add_argument("--output", required=True, type=Path, help="Input JSON path; gold.json is written next to it")
    ex.add_argument("--private-pack", type=Path, help="Custodian-provided holdout .cases file stored outside the repository")
    verify = sub.add_parser("verify")
    verify.add_argument("--private-pack", type=Path)
    args = parser.parse_args()
    if args.private_pack and args.private_pack.resolve().is_relative_to(ROOT.parents[1]):
        parser.error("Keep the private pack outside the repository.")
    if args.command == "export":
        if args.split == "holdout" and not args.private_pack:
            parser.error("The custodian must supply --private-pack for a holdout export.")
        if args.split == "holdout" and args.output.resolve().is_relative_to(ROOT.parents[1]):
            parser.error("Keep the generated holdout and answers outside the repository.")
        if args.output.name == "gold.json":
            parser.error("Choose an input filename distinct from gold.json.")
        pack = args.private_pack if args.split == "holdout" else ROOT / "corpus" / (args.split + ".cases")
        inputs, gold = make(args.split, pack)
        verify_fingerprint(args.split, pack, inputs, gold)
        args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        write_json(args.output, inputs)
        write_json(args.output.parent / "gold.json", gold)
    else:
        all_text, all_rows, all_families = set(), set(), set()
        previous_templates = []
        for split in FAMILY_COUNT:
            if split == "holdout" and args.private_pack is None:
                continue
            pack = args.private_pack if split == "holdout" else ROOT / "corpus" / (split + ".cases")
            inputs, gold = make(split, pack)
            verify_fingerprint(split, pack, inputs, gold)
            templates = [re.sub(r"\{[^}]+\}", "x", phrase.lower()).split()
                         for recipes in load_recipes(pack).values() for _, phrase in recipes]
            if any(SequenceMatcher(None, a, b).ratio() > 0.85 for a in templates for b in previous_templates):
                raise ValueError("Cross-split near duplicate in normalized query templates")
            previous_templates.extend(templates)
            text = {q["text"].casefold() for q in inputs["queries"]}
            ids = {r["id"] for h in inputs["histories"] for r in h["workouts"]}
            families = {q["family"] for q in inputs["queries"]}
            if text & all_text or ids & all_rows or families & all_families:
                raise ValueError("Cross-split collision of wording, workouts or scenario families")
            all_text.update(text)
            all_rows.update(ids)
            all_families.update(families)
            print(f"{split}: {len(text)} queries, {len(families)} scenario families, {len(ids)} workouts")


if __name__ == "__main__":
    main()
