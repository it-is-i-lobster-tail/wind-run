# Wind Run

<img src="Branding/logo.svg" width="160" alt="Wind Run logo: a black and white cat sprinting">

A quiet running app for iPhone and Apple Watch. Tap start, run, and see where you went. Turn on pace call-outs in Settings to hear each split read aloud, every distance (¼ mi to 5 mi, or 250 m to 5 km) or every stretch of time (30 sec to 30 min). Coach plans and interval workouts are on the way, for anyone training between a 5K and a marathon.

Privacy first: runs and routes are stored on the device with SwiftData. iCloud sync is off until the runner turns it on, and turning it off deletes the iCloud copy. There's no account and no analytics. Settings (units and call-outs) pass directly between your paired iPhone and Apple Watch, and call-outs are spoken on the device.

Apple Health is optional and off by default. Turn on Save runs to Health in Settings (on the phone and on the watch) and each finished run is added to Health as an outdoor running workout with its distance, pauses and route. Turning it off stops new runs from being saved; workouts already in Health stay there.

Heart rate is optional too, and off by default. The first time Wind Run opens on each device it asks whether to turn it on, and it can be changed later in Settings. With it on, each run starts a HealthKit workout session, which passes along live heart rate from an Apple Watch, AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap paired in Settings. Readings are kept with the run in Wind Run's store. The run screens show the current heart rate, and the run detail charts heart rate over the whole run with its minimum, maximum, mean and variance. Heart rate is the only thing Wind Run reads from Health. The session's own workout is always discarded, so only Save runs to Health ever adds a run to Health. On the watch, the session also keeps the app running with the wrist down.

On iPhone, a run with heart rate on also shows a Live Activity on the Lock Screen and in the Dynamic Island: the current heart rate and a graph of the last five minutes. The app updates it on the device, with no push server, and it ends with the run. Runs recorded only on the watch don't get one yet.

## Project

- `WindRun.xcodeproj` with four targets:
  - `WindRun`: the iPhone app. It embeds the watch app and the Live Activity.
  - `WindRunWatch`: the Apple Watch app. It runs on its own with its own local store.
  - `WindRunLiveActivity`: the iPhone heart rate Live Activity. `LiveActivityShared/` holds what it and the app both compile.
  - `WindRunTests`: Swift Testing unit tests for the models.
- `Shared/` is compiled into both apps: SwiftData models, the GPS `RunRecorder`, pace call-outs, settings sync, formatting, the optional Apple Health sync (`HealthSync`), live heart rate (`HeartRateMonitor`), and first-open prompts (`Shared/Prompts/`: add a `Prompt` to `Prompt.all` when a feature needs the runner's go-ahead; each device asks it once).
- The iPhone app keeps recording and speaking with the phone locked (`audio` and `location` background modes in `WindRun/Info.plist`).
- If the system closes the app mid-run, the next launch finishes that run at its last GPS fix or heart rate reading (`RunRecovery`), so it shows in the list. A run that recorded nothing is deleted.
- Folders are file-system-synchronized, so new `.swift` files are picked up without editing the project file.
- `Branding/logo.svg` is the logo source. The app icons in both asset catalogs are 1024 px renders of it; the watch one is scaled to 86% so the paws and tail clear the round mask.
- SwiftUI and SwiftData only, no third-party dependencies. iOS 26 and watchOS 26. Code is main-actor isolated by default.

## Models

| Model | What it is |
| --- | --- |
| `Run` | One recorded run: kind (run, intervals, coach), status, distance, pauses, route, heart rate. |
| `RouteSample` | One GPS fix: time, position, altitude, accuracy, speed, course. |
| `RunPause` | A stretch where the clock was paused. |
| `HeartRateSample` | One heart rate reading, taken while the run was active. |
| `IntervalPlan` → `IntervalBlock` → `IntervalStep` | A saved interval workout. A block repeats its steps, so "10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down" is three blocks. `timeline` writes out every step in order. |
| `CoachPlan` → `CoachWeek` → `CoachWorkout` | A coach plan toward a goal: build distance, speed work, or an event on a date. |

Conventions follow PowerJack: stored properties end in `Value` and are read through accessors, ordered children carry an `order` and are returned sorted, and state changes go through guarded methods that log instead of throwing.

iCloud sync puts two more rules on every model: to-many relationships are optional (`[RouteSample]? = []`), and every relationship has an inverse. `SyncReadinessTests` fails if a model breaks either.

## iCloud sync

Settings → Your Data → iCloud Sync. It's off by default and needs the iPhone to be signed in to iCloud.

- `WindRunStore` (`WindRun/Persistence/`) owns the model container. Turning sync on or off swaps in a new container on the same store file, and the root view rebuilds its screens from it.
- Data goes to the runner's private CloudKit database in `iCloud.com.stanleycloud.WindRun`, in the zone SwiftData mirrors into.
- Turning sync off asks first, closes the syncing container, then deletes that zone. If iCloud can't be reached, nothing is deleted and sync stays on. If the iPhone is signed out, the runner can turn sync off and leave the copy in iCloud.
- The watch keeps its own local store and doesn't sync.

Trying it in the simulator, where nobody is signed in to iCloud: run with `-fakeICloud signedIn`, `-fakeICloud signedOut` or `-fakeICloud unreachable` (debug builds only; both are in the `WindRun` scheme, turned off).

Before a TestFlight or App Store build, after any model change: run from Xcode with `-initCloudKitSchema` while signed in to iCloud, then deploy the Development schema to Production in the CloudKit Console.

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
