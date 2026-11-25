# Workout search benchmark v1

The original validation pack is now a public regression suite. Its follow-up scores measure recovery on known cases. The original blind pack remains in evaluator custody.

The corpus contains 360 synthetic English queries. Its 36 independent scenario groups each have five authored phrasings, two substitutions per phrasing and their own seeded workout history. Development uses 18 groups, validation nine and the sealed evaluation nine. The history generator deliberately repeats boundary constructions across groups. Each group has its own IDs, draws of distractor workouts and geography. Counts of independent scenarios are therefore smaller than counts of query strings. No personal workout or search data is used.

Start times use UTC ISO 8601. Relative dates use November 25, 2026 at noon in America/Los_Angeles, a Gregorian calendar and Sunday as the first day of the week. Distances use meters and active durations use seconds. Paused workouts also carry a longer elapsed duration. Missing starts have null place fields. Place labels describe the workout start. Identical measurements can have multiple valid first-place IDs. Ranking ties across dates let the scorer accept either first workout.

The independent corpus author paired each query template with a declarative intent, before seeing the production prompt or search results. These synthetic cases have not received human relevance judgments. The Python generator evaluates the annotations against workout facts. A second implementation uses SQLite to verify every eligible ID, filter-specific membership, clarification choice and first-place tie from the exported JSON. Concrete examples separately verify the CA/California and IN/Indiana equivalences, Portland ambiguity, strict 20-mile boundary, paused duration and empty histories. These tests check the oracle's execution. A human reviewer can still identify an ambiguous wording or a mistaken label. Revise such an item under a new corpus version.

## Generate public inputs and keys

Run from the repository root with Python 3.9 or later. Use one output directory per split. The simulator receives only the input file. Gold and the reporting metadata never enter the model instructions.

~~~sh
python3 scripts/search-evaluation/corpus.py verify
python3 scripts/search-evaluation/corpus.py export --split development --output /tmp/wr-development/corpus.json
python3 scripts/search-evaluation/audit_corpus.py --corpus /tmp/wr-development/corpus.json --gold /tmp/wr-development/gold.json
~~~

Replace `development` with `validation` for the validation scorer. The input contains the fixture histories, case IDs, text, intent category and preregistered slice flags. `conversational` is assigned when a wording template is authored. `boundary` identifies date and numeric constraint cases, and `exclusion` identifies negation. Gold records include expected action, eligible IDs, tied top IDs, the expected place choices, canonical filter values, and the IDs allowed by each individual filter. Rankings use active duration per meter for fastest and recorded meters for longest.

## Blind custody and reproducibility

The v1 custodian stores the owner-readable case pack at `~/Library/Application Support/Wind Run/Search Evaluation/holdouts/v1/holdout.cases`. Back up this file privately when moving the benchmark to another evaluation host. The pack's SHA-256 is `c07aaa9bfbce27e16da97d90786933d7fdc950a6ce3b298526a160f62b2c8fc3`. The repository stores the recipe, generated input and gold fingerprints for all three splits in `v1-fingerprints.json`. Generation refuses to export results that differ from the frozen fingerprints.

A blind evaluator may run the following with its private pack. Keep the pack, gold, query-level logs and transcripts in private custody. Give the prompt author aggregate results only.

~~~sh
custody="$HOME/Library/Application Support/Wind Run/Search Evaluation/holdouts/v1"
python3 scripts/search-evaluation/corpus.py verify --private-pack "$custody/holdout.cases"
python3 scripts/search-evaluation/corpus.py export --split holdout --private-pack "$custody/holdout.cases" --output "$custody/export/corpus.json"
python3 scripts/search-evaluation/audit_corpus.py --corpus "$custody/export/corpus.json" --gold "$custody/export/gold.json"
~~~

Verification checks cross-split case wording, workout IDs, family IDs and normalized phrasing templates. Two templates fail the near-duplicate check when their token sequence similarity exceeds 0.85 after placeholder and case normalization. This check does not establish natural-language independence or production representativeness. Compare candidates on the same frozen inputs, bootstrap by scenario family, and collect new independently written histories and queries when confidence is insufficient. When blind failures have been inspected, retire those scenarios from release gating and author a fresh private pack.

## Independent generalization challenge

The v2 challenge contains 72 individually written English questions, 56 fictional workouts and 12 new histories. A separate evaluation agent wrote the workout facts, question wording and explicit answer IDs before either candidate ran. Each question has independent relevance judgments, including accepted first-place ties and clarification choices. The audit checks these judgments against the annotated constraints using SQLite. The current macOS custodian keeps its private source, input and answer key in `~/Library/Application Support/Wind Run/Search Evaluation/challenges/v2/`. The public registry is `v2-challenge-fingerprints.json`. The release holdout remains separate.

To reproduce the exact files in a fresh private directory, run:

~~~sh
challenge="$HOME/Library/Application Support/Wind Run/Search Evaluation/challenges/v2"
python3 scripts/search-evaluation/freeze_challenge.py --private-pack "$challenge/challenge.cases" --output "$challenge/reproduced"
~~~

Both builds consume the same input. Interpret results at the scenario-family level. The set covers 47 conversational questions and 37 with numeric, date or exclusion constraints. Three clarification questions and five targeted lookups give those intent slices limited statistical precision.
