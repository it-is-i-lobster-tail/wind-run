# Engine replay without a simulator

`evaluate.py` compiles the search engine's Foundation-only sources (`WorkoutSearchEngine.swift`,
`WorkoutSearchVocabulary.swift`, `WorkoutSearchScoring.swift`) with `swiftc` into a small command-line
replay, then scores all three sets in a few seconds: the development set, the validation recovery set and
the annual weekly replay. It works on macOS and on Linux with a Swift 6.2 or later toolchain.

```sh
python3 scripts/search-evaluation/engine-harness/evaluate.py --failures /tmp/search-misses.json
python3 scripts/search-evaluation/engine-harness/evaluate.py --debug "runs over 5 km in Portand"
WR_PERF=1 python3 scripts/search-evaluation/engine-harness/evaluate.py   # 1,000-workout timing
```

Best matches are graded as the result list, the same way the simulator benchmark grades `ids`. Close
matches only count toward two extra measures: `top3` (the right workout is among the first three rows on
screen) and `emptyScreens` (an expected workout exists, yet the screen shows neither best nor close matches).

Route profiles become the facts the app's index would store: `climb` is uphill, `descent` downhill,
`outBack` both, and the other profiles have no steep stretch. The simulator benchmark records real GPS
routes instead, so it stays the reference. This replay is for fast iteration while changing the engine.
