# Linked annual simulator replay

The annual study can run its deterministic search lane on an already booted iOS simulator using a small command-line executable. It loads the app’s Debug library and uses the annual benchmark’s SwiftData seeding, GPS route recording, weekly history cutoff, search call and observation format. The normal study script still assigns runners, prepares each trial and writes the grader’s answer files.

## Build

Use Apple Silicon, Xcode and an iOS Simulator Debug build of Wind Run. Build the app and its test module from the checkout under evaluation. Set `STUDY_SIMULATOR` to one of the project’s iOS simulator UUIDs. Run these commands from the repository root.

```sh
STUDY_BUILD="$(mktemp -d)"
DRIVER_DIR="$(mktemp -d)"
xcodebuild -project WindRun.xcodeproj -scheme WindRun -configuration Debug \
  -destination "id=$STUDY_SIMULATOR" -derivedDataPath "$STUDY_BUILD" build-for-testing
CONFIGURATION="$(find "$STUDY_BUILD/Build/Products" -maxdepth 1 -name 'WindRun_*.xctestrun' -print -quit)"
python3 scripts/search-evaluation/year-study/linked_replay.py build \
  --configuration "$CONFIGURATION" --driver-dir "$DRIVER_DIR"
```

Keep both directories until the trial finishes. Rebuild the driver after rebuilding the app or changing the benchmark fixture. Each build records the app, compiled driver, generated source, benchmark and synthetic route hashes.

## Replay one trial

Set `ASSIGNMENTS` to the study’s JSON mapping from runner IDs to ten distinct booted simulator UUIDs. Set `TRIAL` to a number from 1 through 5 and `OUTPUT` to the results directory for that trial and build. The fixture directory in the command is the standard annual study input.

```sh
python3 scripts/search-evaluation/year-study/linked_replay.py replay \
  --driver-dir "$DRIVER_DIR" --configuration "$CONFIGURATION" \
  --runs scripts/search-evaluation/year-study/fixtures --assignments "$ASSIGNMENTS" \
  --trial "$TRIAL" --output "$OUTPUT" --workers 2
```

Each runner checks its assigned simulator UUID and hashes the app library loaded inside that simulator. Its attempt directory contains the prepared queries, observations and a manifest. The study writes `answers.jsonl` and the completion receipt in the runner directory for grading and resuming.

For a parity check, run the same trial through `scripts/search-evaluation/year_study.py` with the same arguments, omitting `--driver-dir` and using a separate output directory. Compare the query IDs, actions and ordered workout IDs in each runner’s answer file.

## Grade the replay

Run the grader after all ten receipts are present.

```sh
python3 -B scripts/search-evaluation/year_grader.py --trial "$TRIAL" \
  --runs scripts/search-evaluation/year-study/fixtures --output "$OUTPUT"
```

The grader writes query-level diagnostics and a score for the trial. The [study report](report.md) summarizes the completed trials.
