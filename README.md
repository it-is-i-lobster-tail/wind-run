# Wind Run

A quiet running app for iPhone and Apple Watch. Tap start, run, and see where you went. Coach plans and interval workouts are on the way, for anyone training between a 5K and a marathon.

Privacy first: runs and routes are stored on the device with SwiftData. There's no account, no iCloud sync, and no analytics.

Apple Health is optional and off by default. Turn on Save runs to Health in Settings (on the phone and on the watch) and each finished run is added to Health as an outdoor running workout with its distance, pauses and route. Wind Run only writes to Health and never reads from it. Turning it off stops new runs from being saved; workouts already in Health stay there.

## Project

- `WindRun.xcodeproj` with three targets:
  - `WindRun`: the iPhone app. It embeds the watch app.
  - `WindRunWatch`: the Apple Watch app. It runs on its own with its own local store.
  - `WindRunTests`: Swift Testing unit tests for the models.
- `Shared/` is compiled into both apps: SwiftData models, the GPS `RunRecorder`, formatting, and the optional Apple Health sync (`HealthSync`).
- Folders are file-system-synchronized, so new `.swift` files are picked up without editing the project file.
- SwiftUI and SwiftData only, no third-party dependencies. iOS 26 and watchOS 26. Code is main-actor isolated by default.

## Models

| Model | What it is |
| --- | --- |
| `Run` | One recorded run: kind (run, intervals, coach), status, distance, pauses, route. |
| `RouteSample` | One GPS fix: time, position, altitude, accuracy, speed, course. |
| `RunPause` | A stretch where the clock was paused. |
| `IntervalPlan` → `IntervalBlock` → `IntervalStep` | A saved interval workout. A block repeats its steps, so "10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down" is three blocks. `timeline` writes out every step in order. |
| `CoachPlan` → `CoachWeek` → `CoachWorkout` | A coach plan toward a goal: build distance, speed work, or an event on a date. |

Conventions follow PowerJack: stored properties end in `Value` and are read through accessors, ordered children carry an `order` and are returned sorted, and state changes go through guarded methods that log instead of throwing.

## Build and test

```bash
# iPhone app (builds the watch app too)
xcodebuild -project WindRun.xcodeproj -scheme WindRun \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build

# Watch app on its own
xcodebuild -project WindRun.xcodeproj -scheme WindRunWatch \
  -destination 'generic/platform=watchOS Simulator' build

# Unit tests
xcodebuild -project WindRun.xcodeproj -scheme WindRun \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

To try a run in the simulator, feed it a route: `xcrun simctl location booted start --speed=3.5 37.7749,-122.4194 37.7800,-122.4194`.
