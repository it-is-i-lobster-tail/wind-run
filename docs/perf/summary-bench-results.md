# Summary and compare page load benchmark: results

Investigation only. Produced by `WindRunTests/SummaryLoadBenchmarkTests.swift` (skipped unless `WINDRUN_BENCH=1`).
All times are milliseconds on the main thread. Run counts (`fixes`, `mapSegments`, `mapPoints`, `routePointsPerRun`) are counts, not ms.

## Setup

- Mac: MacBook Pro (Mac17,8), Apple M5 Pro, 64 GB, macOS 27.2.1
- Xcode 27.2 (27B52)
- Simulator: a fresh "bench-iphone", iPhone 17 Pro, iOS 27.2 (24B8117), deleted afterwards
- Scheme `WindRun`, `-only-testing:WindRunTests/SummaryLoadBenchmarkTests`, `-parallel-testing-enabled NO`, `TEST_RUNNER_WINDRUN_BENCH=1`
- Debug: `-configuration Debug` (swiftc `-Onone`)
- -O: `-configuration Debug SWIFT_OPTIMIZATION_LEVEL=-O` (confirmed `-O` on the swiftc lines; `@testable import` still worked)
- The test file compiled and passed unchanged; no fix was needed.

## Headline

| | Debug | -O |
|---|---:|---:|
| Summary data, 60 min run (open 1) | 334–344 | 309–319 |
| Summary data, 240 min run (open 1) | 1424–1470 | 1319–1340 |
| Whole summary page, 60 min (open 1, layout total) | 547–573 | 505–511 |
| Whole summary page, 240 min (open 1, layout total) | 1482–1562 | 1395–1402 |
| Second open of the same run, 240 min page | 1516–1554 | 1402–1425 |
| Compare suggestions, 30 runs (open 1) | 4101–4203 | 3949–4134 |
| Compare series, 3 runs | 453–474 | 402–462 |
| Compare page layout, series ready | 526–1081 | 531–551 |

What the numbers say:

1. **Optimisation barely helps (≈5–10%).** The time is not in Wind Run's own arithmetic, it is in reading SwiftData `@Model` properties. The only stages -O speeds up a lot (`altitudeTrack`, `coloredRoutes`, `paceTimeline`, `calories`) were already small.
2. **A second open costs the same as the first.** Nothing is cached between opens; the summary is rebuilt from the model every time (only `startLocation` gets faster on open 2, because the objects are already faulted in).
3. **`Run.route` and `Run.activeRoute` are most of the summary.** For 240 min: `route` ≈ 390 ms, `activeRoute` ≈ 600 ms (it calls `route` again inside), `startLocation` ≈ 150 ms, `heartRateChart` ≈ 90 ms. Drawing the charts and the map on their own is cheap (pace chart ≈ 17 ms, heart chart ≈ 42 ms, map ≈ 100 ms).
4. **The compare page's suggestions are the slowest thing measured: ≈ 4 s for 30 runs.** `ComparisonSuggestions.init` → `ProgressGroup.rank(_:)` → `run.activeRoute` for every run in the group, so it is the per-run `activeRoute` cost times 30. Opening it again costs ≈ 3.4 s, again nothing cached.
5. Cost scales linearly with the number of route fixes (30 → 60 → 240 min ≈ 1 : 2 : 8.8).

## Time Profiler

Recorded with `xcrun xctrace record --template 'Time Profiler' --device <UDID> --attach <pid>` around a single test, -O build, exported with `xctrace export` (`time-profile` table) and aggregated by a small script over main-thread samples (1 ms per sample).

### testSummaryPageRender (60 + 240 min runs, two opens each, plus chart-only renders)

Main thread: 8.6 s sampled, of which 2.2 s is the test building its own fake runs (`addRun`, excluded below) and 3.85 s is inside `render(...)` (the page itself).

Inside `render(...)`, the heaviest Wind Run frames (total weight):

| Total ms | Symbol |
|---:|---|
| 2488 | `RunDetailView.buildSummary()` / `RunDetailView.Summary.init(_:)` (called from `onAppear`) |
| 1561 | `Run.activeRoute.getter` |
| 1224 | `RouteSample.timestampValue.getter` (SwiftData getter) |
| 1142 | `Sequence.sorted(by:)` / `_stableSortImpl` (the sort in `Run.route`) |
| 992 | `Run.route.getter` |
| 391 | `Run.startLocation.getter` |
| 292 | `Run.routeSamplesValue.getter` (relationship fault) |
| 266 | `Sequence.contains(where:)` (the pause checks in `activeRoute`) |
| 264 | `RouteSample.latitudeValue.getter` |
| 234 | `Run.heartRateChart(buffers:)` |
| 189 | `Run.heartRateSamples.getter` |
| 187 | `Run.activeTime(at:)` |
| 162 | `RunPause.startDateValue.getter` |
| 156 | `HeartRateSample.timestampValue.getter` |
| 142 | `Run.coloredRoutes(fixes:track:cadence:)` |

Heaviest framework frames by total weight in the same window: SwiftUI's own update/layout ≈ 1.36 s outside `Summary.init`, and `_swift_getKeyPath(pattern:arguments:)` **934 ms**, with `swift_getTypeByMangledName` ≈ 625 ms beneath it.

Top self weight inside `render(...)`: `_platform_memmove` 154, `tryCast` 130, `swift_conformsToProtocolMaybeInstantiateSuperclasses` 100, `Hasher._combine` 84, Swift demangler 59, `AnyKeyPath.==` 54, `Hasher._finalize` 47, `swift_release` 46, `swift_getTypeByMangledNameImpl` 45, refcount decrement 44, `_pop(from:as:count:)` 42, `demangleType` 41, `swift_getTypeByMangledNodeImpl` 41, refcount increment 39, `pthread_getspecific` 38 (all ms).

Where `_swift_getKeyPath` is called from (nearest Wind Run frame): `RouteSample.timestampValue.getter` 562 ms, `RouteSample.latitudeValue.getter` 99, `HeartRateSample.timestampValue.getter` 81, `RunPause.startDateValue.getter` 80, `RouteSample.longitudeValue.getter` 40, `RunPause.endDateValue.getter` 37.

So **each read of a SwiftData property builds a key path at runtime** (key path instantiation, demangling, type lookup, hashing, casting), and `Run.route` reads `timestamp` twice per comparison in an O(n log n) sort; 956 ms of the 1224 ms in the `timestamp` getter is inside that sort. `activeRoute` then reads `timestamp` several more times per fix (`pauses.contains`, the gap check, `activeTime(at:)`), and reads every pause's `startDate`/`endDate` for every fix.

### testComparison (30 runs of 50 min, suggestions twice, series, page)

All 7.17 s of the profiled suggestions work is `ComparisonSuggestions.init` → `ProgressGroup.rank(_:)` → `Run.activeRoute.getter` (7166 ms). Within it: `Run.route.getter` 4564 ms, `RouteSample.timestampValue.getter` 4415 ms (3690 ms of it inside the sort, 2237 ms of it in `_swift_getKeyPath`), `Sequence.contains(where:)` 1171 ms, `RunPause.startDateValue.getter` 740 ms, `Run.routeSamplesValue.getter` 719 ms, `DistanceEstimator.Fix.init` 636 ms, `Run.activeTime(at:)` 610 ms, `RouteSample.latitudeValue.getter` 522 ms, `Run.pausedTime(at:)` 487 ms, `RunPause.duration(at:)` 432 ms, `RunPause.endDateValue.getter` 326 ms, `RunPause.contains(_:)` 307 ms.

## Leads (not acted on)

- Sort once on plain values: read each fix's `timestamp` once into an array of `(Date, RouteSample)` (or a plain struct copy of the fix) and sort that, instead of calling the SwiftData getter inside the comparator. Same for `heartRateSamples`, `pauses` and `startLocation`.
- Make `activeRoute` take plain pause intervals (`[(start, end)]`) read once, and walk pauses with a moving index instead of `contains(where:)` per fix; compute `activeTime` incrementally.
- Cache the summary per run (for example keyed by run ID and sample count) so a second open is free, and build it off the main thread from plain values.
- For comparisons, `rank` only needs the goal crossing time; store it on the run when it finishes (or cache per run) instead of rebuilding `activeRoute` for every run in the group on every open.

## Raw BENCH lines

Both runs of each build, side by side:

| Measurement | Debug run 1 | Debug run 2 | -O run 1 | -O run 2 |
|---|---:|---:|---:|---:|
| `compare.fetchAll` | 26.6 | 25.4 | 26.4 | 25.9 |
| `compare.suggestions(30 runs).open1` | 4203.2 | 4100.7 | 4133.5 | 3949.4 |
| `compare.suggestions(30 runs).open2` | 3438.9 | 3432.7 | 3416.7 | 3291.9 |
| `compare.series(3 runs).open1` | 473.6 | 464.0 | 462.0 | 409.6 |
| `compare.series(3 runs).open2` | 459.3 | 452.7 | 425.1 | 402.1 |
| `compare.routePointsPerRun` | 3000.0 | 3000.0 | 3000.0 | 3000.0 |
| `compare.page(series ready).firstPass` | 1062.7 | 508.9 | 534.6 | 514.9 |
| `compare.page(series ready).layoutTotal` | 1080.9 | 525.9 | 550.9 | 531.2 |
| `30min.fetchRun` | 1.9 | 1.9 | 2.0 | 1.8 |
| `30min.open1.startLocation` | 18.8 | 18.1 | 19.0 | 17.8 |
| `30min.open1.route(sorted, faults fixes)` | 42.3 | 43.0 | 41.4 | 41.9 |
| `30min.open1.activeRoute` | 70.7 | 69.4 | 67.6 | 66.9 |
| `30min.open1.altitudeTrack` | 6.5 | 6.1 | 3.7 | 3.7 |
| `30min.open1.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `30min.open1.cadenceSeries` | 1.8 | 1.8 | 1.6 | 1.5 |
| `30min.open1.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `30min.open1.coloredRoutes` | 12.1 | 11.7 | 7.0 | 6.5 |
| `30min.open1.paceTimeline` | 2.0 | 1.9 | 1.1 | 1.2 |
| `30min.open1.elevation` | 0.1 | 0.1 | 0.0 | 0.0 |
| `30min.open1.calories` | 1.4 | 1.3 | 0.1 | 0.1 |
| `30min.open1.heartRateChart(faults readings)` | 10.8 | 10.7 | 10.1 | 9.9 |
| `30min.open1.stepTotal` | 0.1 | 0.1 | 0.1 | 0.1 |
| `30min.open1.TOTAL` | 166.9 | 164.4 | 152.0 | 149.9 |
| `30min.open1.fixes` | 1800.0 | 1800.0 | 1800.0 | 1800.0 |
| `30min.open1.mapSegments` | 76.0 | 76.0 | 76.0 | 76.0 |
| `30min.open1.mapPoints` | 324.0 | 324.0 | 324.0 | 324.0 |
| `30min.open2.startLocation` | 4.5 | 4.4 | 4.4 | 4.2 |
| `30min.open2.route(sorted, faults fixes)` | 42.5 | 42.2 | 41.2 | 41.3 |
| `30min.open2.activeRoute` | 70.0 | 69.7 | 67.1 | 66.7 |
| `30min.open2.altitudeTrack` | 6.6 | 6.2 | 3.8 | 3.6 |
| `30min.open2.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `30min.open2.cadenceSeries` | 1.9 | 1.8 | 1.6 | 1.6 |
| `30min.open2.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `30min.open2.coloredRoutes` | 12.3 | 11.6 | 7.0 | 6.4 |
| `30min.open2.paceTimeline` | 2.0 | 1.9 | 1.2 | 1.2 |
| `30min.open2.elevation` | 0.1 | 0.1 | 0.0 | 0.0 |
| `30min.open2.calories` | 1.4 | 1.3 | 0.1 | 0.1 |
| `30min.open2.heartRateChart(faults readings)` | 9.1 | 8.8 | 8.1 | 8.0 |
| `30min.open2.stepTotal` | 0.1 | 0.1 | 0.1 | 0.1 |
| `30min.open2.TOTAL` | 150.7 | 148.2 | 134.7 | 133.3 |
| `30min.open2.fixes` | 1800.0 | 1800.0 | 1800.0 | 1800.0 |
| `30min.open2.mapSegments` | 76.0 | 76.0 | 76.0 | 76.0 |
| `30min.open2.mapPoints` | 324.0 | 324.0 | 324.0 | 324.0 |
| `60min.fetchRun` | 1.3 | 1.3 | 1.3 | 1.3 |
| `60min.open1.startLocation` | 36.9 | 35.8 | 36.9 | 35.5 |
| `60min.open1.route(sorted, faults fixes)` | 90.3 | 87.9 | 85.0 | 86.1 |
| `60min.open1.activeRoute` | 146.2 | 141.9 | 137.4 | 146.5 |
| `60min.open1.altitudeTrack` | 13.1 | 12.6 | 7.6 | 7.8 |
| `60min.open1.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `60min.open1.cadenceSeries` | 3.7 | 3.5 | 3.2 | 3.3 |
| `60min.open1.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `60min.open1.coloredRoutes` | 24.1 | 23.2 | 14.0 | 13.8 |
| `60min.open1.paceTimeline` | 4.1 | 4.0 | 2.4 | 2.7 |
| `60min.open1.elevation` | 0.1 | 0.1 | 0.0 | 0.0 |
| `60min.open1.calories` | 2.8 | 2.6 | 0.2 | 0.2 |
| `60min.open1.heartRateChart(faults readings)` | 22.4 | 21.5 | 21.5 | 22.8 |
| `60min.open1.stepTotal` | 0.2 | 0.2 | 0.2 | 0.2 |
| `60min.open1.TOTAL` | 344.1 | 333.6 | 308.7 | 319.1 |
| `60min.open1.fixes` | 3600.0 | 3600.0 | 3600.0 | 3600.0 |
| `60min.open1.mapSegments` | 152.0 | 152.0 | 152.0 | 152.0 |
| `60min.open1.mapPoints` | 652.0 | 652.0 | 652.0 | 652.0 |
| `60min.open2.startLocation` | 9.1 | 8.8 | 8.6 | 8.7 |
| `60min.open2.route(sorted, faults fixes)` | 90.7 | 87.7 | 84.8 | 89.5 |
| `60min.open2.activeRoute` | 146.3 | 142.3 | 137.7 | 142.2 |
| `60min.open2.altitudeTrack` | 12.8 | 12.5 | 7.5 | 7.3 |
| `60min.open2.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `60min.open2.cadenceSeries` | 3.7 | 3.6 | 3.2 | 3.3 |
| `60min.open2.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `60min.open2.coloredRoutes` | 24.1 | 23.1 | 14.0 | 13.9 |
| `60min.open2.paceTimeline` | 4.0 | 3.9 | 2.4 | 2.3 |
| `60min.open2.elevation` | 0.1 | 0.1 | 0.0 | 0.0 |
| `60min.open2.calories` | 2.8 | 2.7 | 0.2 | 0.2 |
| `60min.open2.heartRateChart(faults readings)` | 18.0 | 17.6 | 17.5 | 17.7 |
| `60min.open2.stepTotal` | 0.2 | 0.2 | 0.2 | 0.2 |
| `60min.open2.TOTAL` | 312.1 | 302.8 | 276.5 | 285.5 |
| `60min.open2.fixes` | 3600.0 | 3600.0 | 3600.0 | 3600.0 |
| `60min.open2.mapSegments` | 152.0 | 152.0 | 152.0 | 152.0 |
| `60min.open2.mapPoints` | 652.0 | 652.0 | 652.0 | 652.0 |
| `240min.fetchRun` | 3.6 | 3.7 | 3.6 | 3.5 |
| `240min.open1.startLocation` | 157.4 | 152.5 | 154.8 | 149.8 |
| `240min.open1.route(sorted, faults fixes)` | 392.9 | 391.9 | 384.3 | 377.1 |
| `240min.open1.activeRoute` | 624.3 | 598.3 | 598.1 | 590.2 |
| `240min.open1.altitudeTrack` | 55.4 | 51.9 | 31.5 | 32.1 |
| `240min.open1.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `240min.open1.cadenceSeries` | 15.0 | 14.0 | 12.6 | 12.8 |
| `240min.open1.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `240min.open1.coloredRoutes` | 100.5 | 94.5 | 57.0 | 55.4 |
| `240min.open1.paceTimeline` | 16.3 | 16.1 | 9.9 | 10.0 |
| `240min.open1.elevation` | 0.4 | 0.4 | 0.0 | 0.0 |
| `240min.open1.calories` | 11.5 | 11.0 | 1.1 | 1.1 |
| `240min.open1.heartRateChart(faults readings)` | 95.6 | 92.8 | 90.1 | 89.3 |
| `240min.open1.stepTotal` | 0.7 | 0.7 | 0.7 | 0.7 |
| `240min.open1.TOTAL` | 1470.4 | 1424.3 | 1340.3 | 1318.9 |
| `240min.open1.fixes` | 14400.0 | 14400.0 | 14400.0 | 14400.0 |
| `240min.open1.mapSegments` | 611.0 | 611.0 | 611.0 | 611.0 |
| `240min.open1.mapPoints` | 2598.0 | 2598.0 | 2598.0 | 2598.0 |
| `240min.open2.startLocation` | 37.3 | 35.3 | 35.0 | 34.9 |
| `240min.open2.route(sorted, faults fixes)` | 391.5 | 380.8 | 380.8 | 412.6 |
| `240min.open2.activeRoute` | 611.3 | 596.4 | 586.6 | 632.9 |
| `240min.open2.altitudeTrack` | 52.6 | 51.1 | 30.7 | 36.4 |
| `240min.open2.chartPauseBuffers` | 0.0 | 0.0 | 0.0 | 0.0 |
| `240min.open2.cadenceSeries` | 14.3 | 14.0 | 12.7 | 12.9 |
| `240min.open2.sections` | 0.0 | 0.0 | 0.0 | 0.0 |
| `240min.open2.coloredRoutes` | 97.3 | 94.6 | 56.3 | 59.0 |
| `240min.open2.paceTimeline` | 16.3 | 16.1 | 9.6 | 11.9 |
| `240min.open2.elevation` | 0.4 | 0.4 | 0.0 | 0.0 |
| `240min.open2.calories` | 11.4 | 11.2 | 1.1 | 1.1 |
| `240min.open2.heartRateChart(faults readings)` | 78.7 | 77.5 | 74.7 | 82.6 |
| `240min.open2.stepTotal` | 0.8 | 0.7 | 0.7 | 0.7 |
| `240min.open2.TOTAL` | 1312.1 | 1278.2 | 1188.2 | 1285.1 |
| `240min.open2.fixes` | 14400.0 | 14400.0 | 14400.0 | 14400.0 |
| `240min.open2.mapSegments` | 611.0 | 611.0 | 611.0 | 611.0 |
| `240min.open2.mapPoints` | 2598.0 | 2598.0 | 2598.0 | 2598.0 |
| `60min.page.open1.firstPass` | 556.1 | 526.1 | 493.7 | 487.1 |
| `60min.page.open1.layoutTotal` | 573.2 | 546.5 | 510.5 | 505.1 |
| `60min.page.open2.firstPass` | 496.6 | 487.4 | 459.8 | 454.6 |
| `60min.page.open2.layoutTotal` | 512.5 | 504.1 | 475.4 | 470.9 |
| `60min.paceChartOnly.firstPass` | 18.3 | 16.3 | 16.4 | 14.6 |
| `60min.paceChartOnly.layoutTotal` | 18.5 | 16.5 | 16.6 | 14.8 |
| `60min.heartChartOnly.firstPass` | 20.8 | 19.5 | 18.8 | 19.1 |
| `60min.heartChartOnly.layoutTotal` | 21.0 | 19.7 | 19.0 | 19.2 |
| `60min.mapOnly.firstPass` | 37.6 | 36.6 | 36.2 | 37.9 |
| `60min.mapOnly.layoutTotal` | 37.8 | 36.9 | 36.4 | 38.1 |
| `240min.page.open1.firstPass` | 1545.4 | 1466.0 | 1379.2 | 1385.9 |
| `240min.page.open1.layoutTotal` | 1561.8 | 1482.0 | 1395.1 | 1401.7 |
| `240min.page.open2.firstPass` | 1499.3 | 1536.8 | 1407.3 | 1386.5 |
| `240min.page.open2.layoutTotal` | 1516.4 | 1554.1 | 1424.6 | 1402.3 |
| `240min.paceChartOnly.firstPass` | 17.4 | 16.7 | 17.2 | 17.2 |
| `240min.paceChartOnly.layoutTotal` | 17.6 | 17.0 | 17.4 | 17.4 |
| `240min.heartChartOnly.firstPass` | 44.2 | 42.6 | 41.4 | 41.1 |
| `240min.heartChartOnly.layoutTotal` | 44.4 | 42.8 | 41.6 | 41.2 |
| `240min.mapOnly.firstPass` | 101.2 | 101.5 | 102.2 | 101.4 |
| `240min.mapOnly.layoutTotal` | 101.5 | 101.7 | 102.4 | 101.7 |

### Debug run 1

```
BENCH|compare.fetchAll|26.6
BENCH|compare.suggestions(30 runs).open1|4203.2
BENCH|compare.suggestions(30 runs).open2|3438.9
BENCH|compare.series(3 runs).open1|473.6
BENCH|compare.series(3 runs).open2|459.3
BENCH|compare.routePointsPerRun|3000.0
BENCH|compare.page(series ready).firstPass|1062.7
BENCH|compare.page(series ready).layoutTotal|1080.9
BENCH|30min.fetchRun|1.9
BENCH|30min.open1.startLocation|18.8
BENCH|30min.open1.route(sorted, faults fixes)|42.3
BENCH|30min.open1.activeRoute|70.7
BENCH|30min.open1.altitudeTrack|6.5
BENCH|30min.open1.chartPauseBuffers|0.0
BENCH|30min.open1.cadenceSeries|1.8
BENCH|30min.open1.sections|0.0
BENCH|30min.open1.coloredRoutes|12.1
BENCH|30min.open1.paceTimeline|2.0
BENCH|30min.open1.elevation|0.1
BENCH|30min.open1.calories|1.4
BENCH|30min.open1.heartRateChart(faults readings)|10.8
BENCH|30min.open1.stepTotal|0.1
BENCH|30min.open1.TOTAL|166.9
BENCH|30min.open1.fixes|1800.0
BENCH|30min.open1.mapSegments|76.0
BENCH|30min.open1.mapPoints|324.0
BENCH|30min.open2.startLocation|4.5
BENCH|30min.open2.route(sorted, faults fixes)|42.5
BENCH|30min.open2.activeRoute|70.0
BENCH|30min.open2.altitudeTrack|6.6
BENCH|30min.open2.chartPauseBuffers|0.0
BENCH|30min.open2.cadenceSeries|1.9
BENCH|30min.open2.sections|0.0
BENCH|30min.open2.coloredRoutes|12.3
BENCH|30min.open2.paceTimeline|2.0
BENCH|30min.open2.elevation|0.1
BENCH|30min.open2.calories|1.4
BENCH|30min.open2.heartRateChart(faults readings)|9.1
BENCH|30min.open2.stepTotal|0.1
BENCH|30min.open2.TOTAL|150.7
BENCH|30min.open2.fixes|1800.0
BENCH|30min.open2.mapSegments|76.0
BENCH|30min.open2.mapPoints|324.0
BENCH|60min.fetchRun|1.3
BENCH|60min.open1.startLocation|36.9
BENCH|60min.open1.route(sorted, faults fixes)|90.3
BENCH|60min.open1.activeRoute|146.2
BENCH|60min.open1.altitudeTrack|13.1
BENCH|60min.open1.chartPauseBuffers|0.0
BENCH|60min.open1.cadenceSeries|3.7
BENCH|60min.open1.sections|0.0
BENCH|60min.open1.coloredRoutes|24.1
BENCH|60min.open1.paceTimeline|4.1
BENCH|60min.open1.elevation|0.1
BENCH|60min.open1.calories|2.8
BENCH|60min.open1.heartRateChart(faults readings)|22.4
BENCH|60min.open1.stepTotal|0.2
BENCH|60min.open1.TOTAL|344.1
BENCH|60min.open1.fixes|3600.0
BENCH|60min.open1.mapSegments|152.0
BENCH|60min.open1.mapPoints|652.0
BENCH|60min.open2.startLocation|9.1
BENCH|60min.open2.route(sorted, faults fixes)|90.7
BENCH|60min.open2.activeRoute|146.3
BENCH|60min.open2.altitudeTrack|12.8
BENCH|60min.open2.chartPauseBuffers|0.0
BENCH|60min.open2.cadenceSeries|3.7
BENCH|60min.open2.sections|0.0
BENCH|60min.open2.coloredRoutes|24.1
BENCH|60min.open2.paceTimeline|4.0
BENCH|60min.open2.elevation|0.1
BENCH|60min.open2.calories|2.8
BENCH|60min.open2.heartRateChart(faults readings)|18.0
BENCH|60min.open2.stepTotal|0.2
BENCH|60min.open2.TOTAL|312.1
BENCH|60min.open2.fixes|3600.0
BENCH|60min.open2.mapSegments|152.0
BENCH|60min.open2.mapPoints|652.0
BENCH|240min.fetchRun|3.6
BENCH|240min.open1.startLocation|157.4
BENCH|240min.open1.route(sorted, faults fixes)|392.9
BENCH|240min.open1.activeRoute|624.3
BENCH|240min.open1.altitudeTrack|55.4
BENCH|240min.open1.chartPauseBuffers|0.0
BENCH|240min.open1.cadenceSeries|15.0
BENCH|240min.open1.sections|0.0
BENCH|240min.open1.coloredRoutes|100.5
BENCH|240min.open1.paceTimeline|16.3
BENCH|240min.open1.elevation|0.4
BENCH|240min.open1.calories|11.5
BENCH|240min.open1.heartRateChart(faults readings)|95.6
BENCH|240min.open1.stepTotal|0.7
BENCH|240min.open1.TOTAL|1470.4
BENCH|240min.open1.fixes|14400.0
BENCH|240min.open1.mapSegments|611.0
BENCH|240min.open1.mapPoints|2598.0
BENCH|240min.open2.startLocation|37.3
BENCH|240min.open2.route(sorted, faults fixes)|391.5
BENCH|240min.open2.activeRoute|611.3
BENCH|240min.open2.altitudeTrack|52.6
BENCH|240min.open2.chartPauseBuffers|0.0
BENCH|240min.open2.cadenceSeries|14.3
BENCH|240min.open2.sections|0.0
BENCH|240min.open2.coloredRoutes|97.3
BENCH|240min.open2.paceTimeline|16.3
BENCH|240min.open2.elevation|0.4
BENCH|240min.open2.calories|11.4
BENCH|240min.open2.heartRateChart(faults readings)|78.7
BENCH|240min.open2.stepTotal|0.8
BENCH|240min.open2.TOTAL|1312.1
BENCH|240min.open2.fixes|14400.0
BENCH|240min.open2.mapSegments|611.0
BENCH|240min.open2.mapPoints|2598.0
BENCH|60min.page.open1.firstPass|556.1
BENCH|60min.page.open1.layoutTotal|573.2
BENCH|60min.page.open2.firstPass|496.6
BENCH|60min.page.open2.layoutTotal|512.5
BENCH|60min.paceChartOnly.firstPass|18.3
BENCH|60min.paceChartOnly.layoutTotal|18.5
BENCH|60min.heartChartOnly.firstPass|20.8
BENCH|60min.heartChartOnly.layoutTotal|21.0
BENCH|60min.mapOnly.firstPass|37.6
BENCH|60min.mapOnly.layoutTotal|37.8
BENCH|240min.page.open1.firstPass|1545.4
BENCH|240min.page.open1.layoutTotal|1561.8
BENCH|240min.page.open2.firstPass|1499.3
BENCH|240min.page.open2.layoutTotal|1516.4
BENCH|240min.paceChartOnly.firstPass|17.4
BENCH|240min.paceChartOnly.layoutTotal|17.6
BENCH|240min.heartChartOnly.firstPass|44.2
BENCH|240min.heartChartOnly.layoutTotal|44.4
BENCH|240min.mapOnly.firstPass|101.2
BENCH|240min.mapOnly.layoutTotal|101.5
```

### Debug run 2

```
BENCH|compare.fetchAll|25.4
BENCH|compare.suggestions(30 runs).open1|4100.7
BENCH|compare.suggestions(30 runs).open2|3432.7
BENCH|compare.series(3 runs).open1|464.0
BENCH|compare.series(3 runs).open2|452.7
BENCH|compare.routePointsPerRun|3000.0
BENCH|compare.page(series ready).firstPass|508.9
BENCH|compare.page(series ready).layoutTotal|525.9
BENCH|30min.fetchRun|1.9
BENCH|30min.open1.startLocation|18.1
BENCH|30min.open1.route(sorted, faults fixes)|43.0
BENCH|30min.open1.activeRoute|69.4
BENCH|30min.open1.altitudeTrack|6.1
BENCH|30min.open1.chartPauseBuffers|0.0
BENCH|30min.open1.cadenceSeries|1.8
BENCH|30min.open1.sections|0.0
BENCH|30min.open1.coloredRoutes|11.7
BENCH|30min.open1.paceTimeline|1.9
BENCH|30min.open1.elevation|0.1
BENCH|30min.open1.calories|1.3
BENCH|30min.open1.heartRateChart(faults readings)|10.7
BENCH|30min.open1.stepTotal|0.1
BENCH|30min.open1.TOTAL|164.4
BENCH|30min.open1.fixes|1800.0
BENCH|30min.open1.mapSegments|76.0
BENCH|30min.open1.mapPoints|324.0
BENCH|30min.open2.startLocation|4.4
BENCH|30min.open2.route(sorted, faults fixes)|42.2
BENCH|30min.open2.activeRoute|69.7
BENCH|30min.open2.altitudeTrack|6.2
BENCH|30min.open2.chartPauseBuffers|0.0
BENCH|30min.open2.cadenceSeries|1.8
BENCH|30min.open2.sections|0.0
BENCH|30min.open2.coloredRoutes|11.6
BENCH|30min.open2.paceTimeline|1.9
BENCH|30min.open2.elevation|0.1
BENCH|30min.open2.calories|1.3
BENCH|30min.open2.heartRateChart(faults readings)|8.8
BENCH|30min.open2.stepTotal|0.1
BENCH|30min.open2.TOTAL|148.2
BENCH|30min.open2.fixes|1800.0
BENCH|30min.open2.mapSegments|76.0
BENCH|30min.open2.mapPoints|324.0
BENCH|60min.fetchRun|1.3
BENCH|60min.open1.startLocation|35.8
BENCH|60min.open1.route(sorted, faults fixes)|87.9
BENCH|60min.open1.activeRoute|141.9
BENCH|60min.open1.altitudeTrack|12.6
BENCH|60min.open1.chartPauseBuffers|0.0
BENCH|60min.open1.cadenceSeries|3.5
BENCH|60min.open1.sections|0.0
BENCH|60min.open1.coloredRoutes|23.2
BENCH|60min.open1.paceTimeline|4.0
BENCH|60min.open1.elevation|0.1
BENCH|60min.open1.calories|2.6
BENCH|60min.open1.heartRateChart(faults readings)|21.5
BENCH|60min.open1.stepTotal|0.2
BENCH|60min.open1.TOTAL|333.6
BENCH|60min.open1.fixes|3600.0
BENCH|60min.open1.mapSegments|152.0
BENCH|60min.open1.mapPoints|652.0
BENCH|60min.open2.startLocation|8.8
BENCH|60min.open2.route(sorted, faults fixes)|87.7
BENCH|60min.open2.activeRoute|142.3
BENCH|60min.open2.altitudeTrack|12.5
BENCH|60min.open2.chartPauseBuffers|0.0
BENCH|60min.open2.cadenceSeries|3.6
BENCH|60min.open2.sections|0.0
BENCH|60min.open2.coloredRoutes|23.1
BENCH|60min.open2.paceTimeline|3.9
BENCH|60min.open2.elevation|0.1
BENCH|60min.open2.calories|2.7
BENCH|60min.open2.heartRateChart(faults readings)|17.6
BENCH|60min.open2.stepTotal|0.2
BENCH|60min.open2.TOTAL|302.8
BENCH|60min.open2.fixes|3600.0
BENCH|60min.open2.mapSegments|152.0
BENCH|60min.open2.mapPoints|652.0
BENCH|240min.fetchRun|3.7
BENCH|240min.open1.startLocation|152.5
BENCH|240min.open1.route(sorted, faults fixes)|391.9
BENCH|240min.open1.activeRoute|598.3
BENCH|240min.open1.altitudeTrack|51.9
BENCH|240min.open1.chartPauseBuffers|0.0
BENCH|240min.open1.cadenceSeries|14.0
BENCH|240min.open1.sections|0.0
BENCH|240min.open1.coloredRoutes|94.5
BENCH|240min.open1.paceTimeline|16.1
BENCH|240min.open1.elevation|0.4
BENCH|240min.open1.calories|11.0
BENCH|240min.open1.heartRateChart(faults readings)|92.8
BENCH|240min.open1.stepTotal|0.7
BENCH|240min.open1.TOTAL|1424.3
BENCH|240min.open1.fixes|14400.0
BENCH|240min.open1.mapSegments|611.0
BENCH|240min.open1.mapPoints|2598.0
BENCH|240min.open2.startLocation|35.3
BENCH|240min.open2.route(sorted, faults fixes)|380.8
BENCH|240min.open2.activeRoute|596.4
BENCH|240min.open2.altitudeTrack|51.1
BENCH|240min.open2.chartPauseBuffers|0.0
BENCH|240min.open2.cadenceSeries|14.0
BENCH|240min.open2.sections|0.0
BENCH|240min.open2.coloredRoutes|94.6
BENCH|240min.open2.paceTimeline|16.1
BENCH|240min.open2.elevation|0.4
BENCH|240min.open2.calories|11.2
BENCH|240min.open2.heartRateChart(faults readings)|77.5
BENCH|240min.open2.stepTotal|0.7
BENCH|240min.open2.TOTAL|1278.2
BENCH|240min.open2.fixes|14400.0
BENCH|240min.open2.mapSegments|611.0
BENCH|240min.open2.mapPoints|2598.0
BENCH|60min.page.open1.firstPass|526.1
BENCH|60min.page.open1.layoutTotal|546.5
BENCH|60min.page.open2.firstPass|487.4
BENCH|60min.page.open2.layoutTotal|504.1
BENCH|60min.paceChartOnly.firstPass|16.3
BENCH|60min.paceChartOnly.layoutTotal|16.5
BENCH|60min.heartChartOnly.firstPass|19.5
BENCH|60min.heartChartOnly.layoutTotal|19.7
BENCH|60min.mapOnly.firstPass|36.6
BENCH|60min.mapOnly.layoutTotal|36.9
BENCH|240min.page.open1.firstPass|1466.0
BENCH|240min.page.open1.layoutTotal|1482.0
BENCH|240min.page.open2.firstPass|1536.8
BENCH|240min.page.open2.layoutTotal|1554.1
BENCH|240min.paceChartOnly.firstPass|16.7
BENCH|240min.paceChartOnly.layoutTotal|17.0
BENCH|240min.heartChartOnly.firstPass|42.6
BENCH|240min.heartChartOnly.layoutTotal|42.8
BENCH|240min.mapOnly.firstPass|101.5
BENCH|240min.mapOnly.layoutTotal|101.7
```

### -O run 1

```
BENCH|compare.fetchAll|26.4
BENCH|compare.suggestions(30 runs).open1|4133.5
BENCH|compare.suggestions(30 runs).open2|3416.7
BENCH|compare.series(3 runs).open1|462.0
BENCH|compare.series(3 runs).open2|425.1
BENCH|compare.routePointsPerRun|3000.0
BENCH|compare.page(series ready).firstPass|534.6
BENCH|compare.page(series ready).layoutTotal|550.9
BENCH|30min.fetchRun|2.0
BENCH|30min.open1.startLocation|19.0
BENCH|30min.open1.route(sorted, faults fixes)|41.4
BENCH|30min.open1.activeRoute|67.6
BENCH|30min.open1.altitudeTrack|3.7
BENCH|30min.open1.chartPauseBuffers|0.0
BENCH|30min.open1.cadenceSeries|1.6
BENCH|30min.open1.sections|0.0
BENCH|30min.open1.coloredRoutes|7.0
BENCH|30min.open1.paceTimeline|1.1
BENCH|30min.open1.elevation|0.0
BENCH|30min.open1.calories|0.1
BENCH|30min.open1.heartRateChart(faults readings)|10.1
BENCH|30min.open1.stepTotal|0.1
BENCH|30min.open1.TOTAL|152.0
BENCH|30min.open1.fixes|1800.0
BENCH|30min.open1.mapSegments|76.0
BENCH|30min.open1.mapPoints|324.0
BENCH|30min.open2.startLocation|4.4
BENCH|30min.open2.route(sorted, faults fixes)|41.2
BENCH|30min.open2.activeRoute|67.1
BENCH|30min.open2.altitudeTrack|3.8
BENCH|30min.open2.chartPauseBuffers|0.0
BENCH|30min.open2.cadenceSeries|1.6
BENCH|30min.open2.sections|0.0
BENCH|30min.open2.coloredRoutes|7.0
BENCH|30min.open2.paceTimeline|1.2
BENCH|30min.open2.elevation|0.0
BENCH|30min.open2.calories|0.1
BENCH|30min.open2.heartRateChart(faults readings)|8.1
BENCH|30min.open2.stepTotal|0.1
BENCH|30min.open2.TOTAL|134.7
BENCH|30min.open2.fixes|1800.0
BENCH|30min.open2.mapSegments|76.0
BENCH|30min.open2.mapPoints|324.0
BENCH|60min.fetchRun|1.3
BENCH|60min.open1.startLocation|36.9
BENCH|60min.open1.route(sorted, faults fixes)|85.0
BENCH|60min.open1.activeRoute|137.4
BENCH|60min.open1.altitudeTrack|7.6
BENCH|60min.open1.chartPauseBuffers|0.0
BENCH|60min.open1.cadenceSeries|3.2
BENCH|60min.open1.sections|0.0
BENCH|60min.open1.coloredRoutes|14.0
BENCH|60min.open1.paceTimeline|2.4
BENCH|60min.open1.elevation|0.0
BENCH|60min.open1.calories|0.2
BENCH|60min.open1.heartRateChart(faults readings)|21.5
BENCH|60min.open1.stepTotal|0.2
BENCH|60min.open1.TOTAL|308.7
BENCH|60min.open1.fixes|3600.0
BENCH|60min.open1.mapSegments|152.0
BENCH|60min.open1.mapPoints|652.0
BENCH|60min.open2.startLocation|8.6
BENCH|60min.open2.route(sorted, faults fixes)|84.8
BENCH|60min.open2.activeRoute|137.7
BENCH|60min.open2.altitudeTrack|7.5
BENCH|60min.open2.chartPauseBuffers|0.0
BENCH|60min.open2.cadenceSeries|3.2
BENCH|60min.open2.sections|0.0
BENCH|60min.open2.coloredRoutes|14.0
BENCH|60min.open2.paceTimeline|2.4
BENCH|60min.open2.elevation|0.0
BENCH|60min.open2.calories|0.2
BENCH|60min.open2.heartRateChart(faults readings)|17.5
BENCH|60min.open2.stepTotal|0.2
BENCH|60min.open2.TOTAL|276.5
BENCH|60min.open2.fixes|3600.0
BENCH|60min.open2.mapSegments|152.0
BENCH|60min.open2.mapPoints|652.0
BENCH|240min.fetchRun|3.6
BENCH|240min.open1.startLocation|154.8
BENCH|240min.open1.route(sorted, faults fixes)|384.3
BENCH|240min.open1.activeRoute|598.1
BENCH|240min.open1.altitudeTrack|31.5
BENCH|240min.open1.chartPauseBuffers|0.0
BENCH|240min.open1.cadenceSeries|12.6
BENCH|240min.open1.sections|0.0
BENCH|240min.open1.coloredRoutes|57.0
BENCH|240min.open1.paceTimeline|9.9
BENCH|240min.open1.elevation|0.0
BENCH|240min.open1.calories|1.1
BENCH|240min.open1.heartRateChart(faults readings)|90.1
BENCH|240min.open1.stepTotal|0.7
BENCH|240min.open1.TOTAL|1340.3
BENCH|240min.open1.fixes|14400.0
BENCH|240min.open1.mapSegments|611.0
BENCH|240min.open1.mapPoints|2598.0
BENCH|240min.open2.startLocation|35.0
BENCH|240min.open2.route(sorted, faults fixes)|380.8
BENCH|240min.open2.activeRoute|586.6
BENCH|240min.open2.altitudeTrack|30.7
BENCH|240min.open2.chartPauseBuffers|0.0
BENCH|240min.open2.cadenceSeries|12.7
BENCH|240min.open2.sections|0.0
BENCH|240min.open2.coloredRoutes|56.3
BENCH|240min.open2.paceTimeline|9.6
BENCH|240min.open2.elevation|0.0
BENCH|240min.open2.calories|1.1
BENCH|240min.open2.heartRateChart(faults readings)|74.7
BENCH|240min.open2.stepTotal|0.7
BENCH|240min.open2.TOTAL|1188.2
BENCH|240min.open2.fixes|14400.0
BENCH|240min.open2.mapSegments|611.0
BENCH|240min.open2.mapPoints|2598.0
BENCH|60min.page.open1.firstPass|493.7
BENCH|60min.page.open1.layoutTotal|510.5
BENCH|60min.page.open2.firstPass|459.8
BENCH|60min.page.open2.layoutTotal|475.4
BENCH|60min.paceChartOnly.firstPass|16.4
BENCH|60min.paceChartOnly.layoutTotal|16.6
BENCH|60min.heartChartOnly.firstPass|18.8
BENCH|60min.heartChartOnly.layoutTotal|19.0
BENCH|60min.mapOnly.firstPass|36.2
BENCH|60min.mapOnly.layoutTotal|36.4
BENCH|240min.page.open1.firstPass|1379.2
BENCH|240min.page.open1.layoutTotal|1395.1
BENCH|240min.page.open2.firstPass|1407.3
BENCH|240min.page.open2.layoutTotal|1424.6
BENCH|240min.paceChartOnly.firstPass|17.2
BENCH|240min.paceChartOnly.layoutTotal|17.4
BENCH|240min.heartChartOnly.firstPass|41.4
BENCH|240min.heartChartOnly.layoutTotal|41.6
BENCH|240min.mapOnly.firstPass|102.2
BENCH|240min.mapOnly.layoutTotal|102.4
```

### -O run 2

```
BENCH|compare.fetchAll|25.9
BENCH|compare.suggestions(30 runs).open1|3949.4
BENCH|compare.suggestions(30 runs).open2|3291.9
BENCH|compare.series(3 runs).open1|409.6
BENCH|compare.series(3 runs).open2|402.1
BENCH|compare.routePointsPerRun|3000.0
BENCH|compare.page(series ready).firstPass|514.9
BENCH|compare.page(series ready).layoutTotal|531.2
BENCH|30min.fetchRun|1.8
BENCH|30min.open1.startLocation|17.8
BENCH|30min.open1.route(sorted, faults fixes)|41.9
BENCH|30min.open1.activeRoute|66.9
BENCH|30min.open1.altitudeTrack|3.7
BENCH|30min.open1.chartPauseBuffers|0.0
BENCH|30min.open1.cadenceSeries|1.5
BENCH|30min.open1.sections|0.0
BENCH|30min.open1.coloredRoutes|6.5
BENCH|30min.open1.paceTimeline|1.2
BENCH|30min.open1.elevation|0.0
BENCH|30min.open1.calories|0.1
BENCH|30min.open1.heartRateChart(faults readings)|9.9
BENCH|30min.open1.stepTotal|0.1
BENCH|30min.open1.TOTAL|149.9
BENCH|30min.open1.fixes|1800.0
BENCH|30min.open1.mapSegments|76.0
BENCH|30min.open1.mapPoints|324.0
BENCH|30min.open2.startLocation|4.2
BENCH|30min.open2.route(sorted, faults fixes)|41.3
BENCH|30min.open2.activeRoute|66.7
BENCH|30min.open2.altitudeTrack|3.6
BENCH|30min.open2.chartPauseBuffers|0.0
BENCH|30min.open2.cadenceSeries|1.6
BENCH|30min.open2.sections|0.0
BENCH|30min.open2.coloredRoutes|6.4
BENCH|30min.open2.paceTimeline|1.2
BENCH|30min.open2.elevation|0.0
BENCH|30min.open2.calories|0.1
BENCH|30min.open2.heartRateChart(faults readings)|8.0
BENCH|30min.open2.stepTotal|0.1
BENCH|30min.open2.TOTAL|133.3
BENCH|30min.open2.fixes|1800.0
BENCH|30min.open2.mapSegments|76.0
BENCH|30min.open2.mapPoints|324.0
BENCH|60min.fetchRun|1.3
BENCH|60min.open1.startLocation|35.5
BENCH|60min.open1.route(sorted, faults fixes)|86.1
BENCH|60min.open1.activeRoute|146.5
BENCH|60min.open1.altitudeTrack|7.8
BENCH|60min.open1.chartPauseBuffers|0.0
BENCH|60min.open1.cadenceSeries|3.3
BENCH|60min.open1.sections|0.0
BENCH|60min.open1.coloredRoutes|13.8
BENCH|60min.open1.paceTimeline|2.7
BENCH|60min.open1.elevation|0.0
BENCH|60min.open1.calories|0.2
BENCH|60min.open1.heartRateChart(faults readings)|22.8
BENCH|60min.open1.stepTotal|0.2
BENCH|60min.open1.TOTAL|319.1
BENCH|60min.open1.fixes|3600.0
BENCH|60min.open1.mapSegments|152.0
BENCH|60min.open1.mapPoints|652.0
BENCH|60min.open2.startLocation|8.7
BENCH|60min.open2.route(sorted, faults fixes)|89.5
BENCH|60min.open2.activeRoute|142.2
BENCH|60min.open2.altitudeTrack|7.3
BENCH|60min.open2.chartPauseBuffers|0.0
BENCH|60min.open2.cadenceSeries|3.3
BENCH|60min.open2.sections|0.0
BENCH|60min.open2.coloredRoutes|13.9
BENCH|60min.open2.paceTimeline|2.3
BENCH|60min.open2.elevation|0.0
BENCH|60min.open2.calories|0.2
BENCH|60min.open2.heartRateChart(faults readings)|17.7
BENCH|60min.open2.stepTotal|0.2
BENCH|60min.open2.TOTAL|285.5
BENCH|60min.open2.fixes|3600.0
BENCH|60min.open2.mapSegments|152.0
BENCH|60min.open2.mapPoints|652.0
BENCH|240min.fetchRun|3.5
BENCH|240min.open1.startLocation|149.8
BENCH|240min.open1.route(sorted, faults fixes)|377.1
BENCH|240min.open1.activeRoute|590.2
BENCH|240min.open1.altitudeTrack|32.1
BENCH|240min.open1.chartPauseBuffers|0.0
BENCH|240min.open1.cadenceSeries|12.8
BENCH|240min.open1.sections|0.0
BENCH|240min.open1.coloredRoutes|55.4
BENCH|240min.open1.paceTimeline|10.0
BENCH|240min.open1.elevation|0.0
BENCH|240min.open1.calories|1.1
BENCH|240min.open1.heartRateChart(faults readings)|89.3
BENCH|240min.open1.stepTotal|0.7
BENCH|240min.open1.TOTAL|1318.9
BENCH|240min.open1.fixes|14400.0
BENCH|240min.open1.mapSegments|611.0
BENCH|240min.open1.mapPoints|2598.0
BENCH|240min.open2.startLocation|34.9
BENCH|240min.open2.route(sorted, faults fixes)|412.6
BENCH|240min.open2.activeRoute|632.9
BENCH|240min.open2.altitudeTrack|36.4
BENCH|240min.open2.chartPauseBuffers|0.0
BENCH|240min.open2.cadenceSeries|12.9
BENCH|240min.open2.sections|0.0
BENCH|240min.open2.coloredRoutes|59.0
BENCH|240min.open2.paceTimeline|11.9
BENCH|240min.open2.elevation|0.0
BENCH|240min.open2.calories|1.1
BENCH|240min.open2.heartRateChart(faults readings)|82.6
BENCH|240min.open2.stepTotal|0.7
BENCH|240min.open2.TOTAL|1285.1
BENCH|240min.open2.fixes|14400.0
BENCH|240min.open2.mapSegments|611.0
BENCH|240min.open2.mapPoints|2598.0
BENCH|60min.page.open1.firstPass|487.1
BENCH|60min.page.open1.layoutTotal|505.1
BENCH|60min.page.open2.firstPass|454.6
BENCH|60min.page.open2.layoutTotal|470.9
BENCH|60min.paceChartOnly.firstPass|14.6
BENCH|60min.paceChartOnly.layoutTotal|14.8
BENCH|60min.heartChartOnly.firstPass|19.1
BENCH|60min.heartChartOnly.layoutTotal|19.2
BENCH|60min.mapOnly.firstPass|37.9
BENCH|60min.mapOnly.layoutTotal|38.1
BENCH|240min.page.open1.firstPass|1385.9
BENCH|240min.page.open1.layoutTotal|1401.7
BENCH|240min.page.open2.firstPass|1386.5
BENCH|240min.page.open2.layoutTotal|1402.3
BENCH|240min.paceChartOnly.firstPass|17.2
BENCH|240min.paceChartOnly.layoutTotal|17.4
BENCH|240min.heartChartOnly.firstPass|41.1
BENCH|240min.heartChartOnly.layoutTotal|41.2
BENCH|240min.mapOnly.firstPass|101.4
BENCH|240min.mapOnly.layoutTotal|101.7
```
