#!/usr/bin/env python3
"""Independently recompute expected actions, result IDs, constraints and top ties from exported facts.

This verifier does not import the corpus generator, search engine or prompt. It uses SQLite and
the annotated intent. Semantic wording still needs independent human or blind-agent review.
"""
import argparse
import json
import sqlite3
from collections import Counter
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo


def require(condition, label):
    if not condition:
        raise ValueError("Corpus audit failed: " + label)


def read_database(corpus):
    db = sqlite3.connect(":memory:")
    db.execute("""CREATE TABLE workouts (
        history TEXT, id TEXT PRIMARY KEY, sport TEXT, kind TEXT, day TEXT, instant TEXT,
        distance REAL, duration INTEGER, city TEXT, state TEXT, abbreviation TEXT, title TEXT, notes TEXT
    )""")
    zone = ZoneInfo(corpus["timeZone"])
    for history in corpus["histories"]:
        for row in history["workouts"]:
            started = datetime.fromisoformat(row["startedAt"].replace("Z", "+00:00"))
            db.execute("INSERT INTO workouts VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (history["id"], row["id"], row["sport"], row["workoutType"],
                        started.astimezone(zone).date().isoformat(), row["startedAt"],
                        row["distanceMeters"], row["activeSeconds"], row["city"], row["stateName"],
                        row["stateCode"], row["title"], row["notes"]))
    return db


def sql_predicate(slot, value):
    if slot in ("distance", "duration"):
        op, raw = value.split(":")
        operator = {"less": "<", "atMost": "<=", "equal": "=", "atLeast": ">=", "greater": ">"}[op]
        return f"{slot} {operator} ?", [float(raw)]
    if slot == "date":
        return "(day >= ? AND day < ?)", value.split("/")
    if slot == "place":
        return "(? IN (lower(city), lower(state), lower(abbreviation), lower(city || ', ' || abbreviation)))", [value]
    if slot in ("notes", "title"):
        return f"instr(lower({slot}), ?) > 0", [value]
    expression = {"sport": "sport = ?", "excludingSport": "sport != ?", "type": "kind = ?",
                  "excludingType": "kind != ?"}[slot]
    return expression, [value]


def audit(inputs, gold):
    db = read_database(inputs)
    by_id = {a["queryID"]: a for a in gold["answers"]}
    counts = Counter()
    for query in inputs["queries"]:
        qid = query["id"]
        a = by_id.pop(qid)
        history = query["historyID"]
        select = " FROM workouts WHERE history = ?"
        clauses = []
        params = [history]
        gold_constraints = {c["slot"]: set(c["allowedIDs"]) for c in a["constraints"]}
        for slot, value in a["slots"].items():
            if slot == "sort":
                continue
            clause, args = sql_predicate(slot, value)
            ids = {r[0] for r in db.execute("SELECT id" + select + " AND " + clause, [history, *args])}
            require(gold_constraints.pop(slot) == ids, f"{qid} {slot}")
            clauses.append(clause)
            params.extend(args)
        require(not gold_constraints, f"{qid} extra constraints")
        if clauses:
            select += " AND " + " AND ".join(clauses)
        distinct_places = [r[0] for r in db.execute(
            "SELECT DISTINCT city || ', ' || abbreviation FROM workouts WHERE history = ? AND lower(city) = ? ORDER BY 1",
            (history, a["slots"].get("place")))]
        state_count = len(distinct_places)
        require(a["placeChoices"] == (distinct_places if state_count > 1 else []), qid + " place choices")
        sort = a["slots"].get("sort")
        score = {None: "instant DESC", "newest": "instant DESC", "oldest": "instant ASC",
                 "longest": "distance DESC", "fastest": "duration / distance ASC"}[sort]
        # Dense rank keeps all tied first-place IDs eligible regardless of tie ordering in Swift.
        rows = list(db.execute(f"SELECT id, dense_rank() OVER (ORDER BY {score})" + select + f" ORDER BY {score}, id", params))
        action = "clarify" if state_count > 1 else ("results" if rows else "empty")
        if action == "clarify":
            rows = []
        require(action == a["action"], qid + " action")
        require(a["ids"] == [wid for wid, _ in rows], qid + " result order")
        top = {wid for wid, rank in rows if rank == 1} if sort else set()
        require(set(a["acceptedTopIDs"]) == top, qid + " top ties")
        require(a["ordered"] == bool(sort), qid + " ordered")
        counts[action] += 1
        counts["ties"] += len(top) > 1
    require(not by_id, "orphaned answers")
    return counts


def anchors(inputs, gold):
    """Concrete, independently worded ground-truth checks for the development bug reports."""
    keyed = {a["queryID"]: a for a in gold["answers"]}
    histories = {h["id"]: h["workouts"] for h in inputs["histories"]}
    by_text = {q["text"]: (histories[q["historyID"]], keyed[q["id"]]) for q in inputs["queries"]}
    for code, state in (("CA", "California"), ("IN", "Indiana")):
        rows, a = by_text[code]
        require(set(by_text[state][1]["ids"]) == set(a["ids"]), "state aliases")
        require(set(a["ids"]) == {r["id"] for r in rows if r["stateCode"] == code}, "start-state constraint")
        require(any(code in r["notes"] and r["id"] not in a["ids"] for r in rows), "note-only red herring")
    rows, over = by_text["rides over 20 miles"]
    _, inclusive = by_text["rides of at least 20 miles"]
    exactly_twenty = {r["id"] for r in rows if r["sport"] == "cycling" and r["distanceMeters"] == 32186.88}
    require(exactly_twenty and set(inclusive["ids"]) - set(over["ids"]) == exactly_twenty, "strict/inclusive mi")
    for q in inputs["queries"]:
        rows = histories[q["historyID"]]
        a = keyed[q["id"]]
        if q["family"] == "moving-clock" and "active time up to" not in q["text"] and "at most" in q["text"]:
            seconds = int(q["text"].split("at most ")[1].split(" ")[0]) * 60
            require(any(r["activeSeconds"] <= seconds < r["elapsedSeconds"] and r["id"] in a["ids"]
                        for r in rows), "duration excludes paused time")
    require(any("Portland" in q["text"] and keyed[q["id"]]["action"] == "clarify" for q in inputs["queries"]),
            "Portland disambiguation")
    require(any("Portland, ME" in q["text"] and keyed[q["id"]]["ids"] for q in inputs["queries"]),
            "qualified Portland")
    require(any(h["workouts"] == [] for h in inputs["histories"]), "empty history")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--corpus", type=Path, required=True)
    p.add_argument("--gold", type=Path, required=True)
    args = p.parse_args()
    corpus = json.loads(args.corpus.read_text())
    gold = json.loads(args.gold.read_text())
    counts = audit(corpus, gold)
    if corpus["split"] == "development":
        anchors(corpus, gold)
    print(f'{corpus["split"]}: {len(corpus["queries"])} keys agree with independent SQL; '
          f'{counts["results"]} results, {counts["empty"]} empty, {counts["clarify"]} clarify, {counts["ties"]} eligible first-place ties')
