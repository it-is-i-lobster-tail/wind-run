# Wind Run

<img src="Branding/logo.svg" width="160" alt="Wind Run logo: a black and white cat sprinting">

A quiet running and cycling app for iPhone and Apple Watch. Start a run or ride and see where you went. Turn on Voice call-outs in Settings to hear each split read aloud, every distance (¼ mi to 5 mi, or 250 m to 5 km) or every stretch of time (30 sec to 30 min), with any of the split's pace, the last mile or kilometer, the run's average, and the pace right now. Coach builds your weekly mileage up to an event, from a 5K to an ultra, and interval workouts are one tap from running. A workout's distance goal can be a race distance (5K, 10K, half marathon or marathon, to the meter), and an interval step can end after a time, after a distance, or "until Next", when the runner taps Next on the run screen, the Lock Screen or the watch. Finish asks first, and a run that looks started by mistake can be thrown away instead. The run screen says when location is off or GPS is weak, with a way to turn location on. The iPhone app follows the iPhone's Light or Dark setting; Settings → Appearance can hold it on Light or Dark instead. The watch is always dark.

Choose **Cycling** on the Workout tab or Apple Watch for an open ride. Custom workouts have a **Workout Type** picker. Settings → Personalization → Voice Call-outs keeps separate distance, time, and spoken metric choices for Running and Cycling. Enabling Cycling call-outs selects Speed by default, announcing each split in km/h or mph. Rides use speed in km/h or mph and stay out of Running Coach mileage. Cycling active calories use moving time, body weight, and outdoor speed bands from the [2024 Adult Compendium of Physical Activities](https://pacompendium.com/bicycling/), subtracting resting energy. Hills, wind, drafting, and electric assistance can change actual effort at a given speed.

Privacy first: runs and routes are stored on the device with SwiftData. iCloud sync is off until the runner turns it on, and turning it off deletes the iCloud copy. There's no account and no analytics. The first time the iPhone app opens it asks for metric or imperial units. Units and call-outs pass directly between your paired iPhone and Apple Watch, and call-outs are spoken on the device from voice clips recorded into the app (`Shared/Callouts/Voice/`, joined by `VoiceScript`), with the system voice for any line no clips cover. With iCloud sync on, every setting goes to iCloud with the runs too.

Apple Health is optional and off by default. The first time Wind Run opens on each device it asks, right after heart rate, whether to save runs to Health, and Save workouts to Health in Settings changes it later. With it on, each finished workout is added to Health as outdoor running or cycling with its distance, pauses, route and the calories Wind Run worked out (so Health asks to save active energy too). A run that couldn't be saved, such as one finished while the iPhone was locked, is tried again when the app comes back. Turning it off stops new runs from being saved; workouts already in Health stay there.

Distance comes from GPS, measured by `DistanceEstimator` (`Shared/Recording/`). Adding up the straight lines between fixes reads several percent long, because at running pace fixes a second apart are about as far apart as the error in each one, and every sideways wobble adds length. So each fix adds its own speed, which the GPS measures from the satellite signal, times the seconds since the fix before. A fix with no usable speed (unknown, less sure than 2 m/s, or after a gap over 10 seconds) adds the straight line from the last good fix instead, and a fix that jumps further than a runner could go (over 9 m/s, or far beyond its own speed) is a spike: it adds nothing by the straight line and is never a starting point. Below 0.4 m/s counts as standing still. Each run keeps which way it was measured (`distanceMethodValue`, nil for runs from before) and the old straight-line sum beside it, and the charts, sections and map colours measure the same way so they add up to the run's distance. Runs recorded earlier keep the distance they had.

With heart rate on, the HealthKit workout session also works out Apple's own distance for the run; Wind Run keeps it beside its own (shown under the run's details, and in the export) but never uses it as the run's distance. Each run also keeps the devices behind it: the iPhone or watch that recorded it and the devices that measured heart rate, each by hardware model (such as "iPhone17,1"), system version and Wind Run version, never by the name the owner gave it. A run recorded on the watch also notes the iPhone it was sent to.

Settings → Your Data → Export Runs saves CSV files to Files for looking at runs offline, either file on its own or both in a zip: `runs.csv` (one row per finished run, numbered oldest first: kind, what recorded it (`recorder_kind`) and every device's versions, Wind Run's distance and how it was measured, the straight-line sum, Apple's distance, both distances worked out again from the GPS points, times, point counts and GPS accuracy) and `gps_points.csv` (one row per GPS point: seconds since the start, the straight-line gap from the point before, accuracy, speed, and what the point added). Before making them it says what's in them and what isn't, and with no finished runs yet it says so rather than saving an empty file. The files are built off the main thread. Nothing in them says where or when the runner ran or who they are: no coordinates, directions, heights, dates or times, heart rate readings, notes, workout names, weight, calories, run ids or device names, and anything in a sensor's details that looks like a serial number is taken out (along with any character that isn't a letter, digit or plain punctuation, so it can't carry a spreadsheet formula). GPS points within 250 m of where a run started or finished, often home, are left out of `gps_points.csv`, though the run's totals still count them. The zip is written by Wind Run itself (`StoredZip`) so its files carry no date or time zone. The files only leave the iPhone if the runner shares them.

Heart rate is optional too, and off by default. The first time Wind Run opens on each device it asks whether to turn it on, and it can be changed later in Settings. With it on, each run starts a HealthKit workout session, which passes along live heart rate from an Apple Watch, AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap paired in Settings. Each reading is tagged with what measured it, and the screens show a dash once readings stop. Readings are kept with the run in Wind Run's store. The run screens show the current heart rate, and the run detail charts heart rate over the whole run with its minimum, maximum, mean and variance. Wind Run reads heart rate and weight from Health, and coach setup reads the last 4 weeks of running workouts to fill in weekly mileage and climb; nothing it reads leaves the device. The session's own workout is always discarded, so only Save workouts to Health ever adds a run to Health. On the watch every run has a workout session, with heart rate on or off, so the app keeps running with the wrist down, and if watchOS closes the app mid-run it picks the run up again from the session watchOS kept going.

Each run shows the calories it burned, worked out on the device from its climb and pace with Minetti's energy cost curves for running and walking on slopes (J Appl Physiol 93:1039, 2002). The run is read 100 m at a time: each stretch's slope is capped at 40% up or down, and a stretch slower than about 9:15 a kilometer (14:54 a mile) counts as walking. Heights come from the barometer when Motion & Fitness is allowed, with GPS setting the level, and otherwise from GPS alone, smoothed over 50 m either side so its wobble doesn't add up to hills. The barometer also gives the run detail its climb and elevation chart. When no GPS height was good enough to set the level, the chart is called Height from start, since its 0 is where the run began rather than the sea. The runner's weight comes from Apple Health when Health has one from the last three months (Wind Run asks to read weight along with its other Health permissions); otherwise the runner can type it on the first-open setup page, or later in Settings. About once a month the app looks in Health again and takes a newer weight. The weight is kept with the other settings, so it goes to iCloud when iCloud Sync is on, and can be changed in Settings. A run's calories are kept with it when it finishes, so a later change of weight leaves old runs as they were.

Coach does one thing: it builds weekly mileage, and climb when the event has hills, up to a peak week by a goal date. Setup is one form. Weekly mileage and climb now are filled in from the last 4 weeks of Wind Run runs and runs other apps saved to Apple Health, and can be changed. Once the plan starts, only runs recorded with Wind Run count toward each week, and setup and the plan screen say so. The runner picks the event and its climb; the distance is the event's own, typed only for a custom event (up to 999 km or mi, climb up to 9,999 m or ft), and the peak week is always 1.5 times both. The runner picks their usual long day. With two run days it gets 60% of the weekly distance. With three or four it gets 50%, and the run after it is the shortest. The week screen lets the runner move one long run, and Plan settings changes the usual day. The final seven days before the event are reserved for easy runs and rest. Adding a target pace gives one shorter run a stretch at that pace. Four-day plans can also include optional speed intervals on the shortest run. Before starting, Change workout can switch a practice session to easy or restore it. A workout can be shortened by 25%, which also lowers that week's target. Easy weeks are 25% under the week before, every few weeks or on weeks the runner taps, and the event week is always one, with the event itself counting toward it. Plan days follow the runner's time zone. A week never adds more than 10% to the last building week. The timeline under the form redraws on every change and shows when the peak comes at 10% and at 5% a week. When even 10% can't get there, the plan still starts and says the goal is ambitious and some walking may be needed. A week under 90% done is repeated, and Report injury holds the mileage (Mild), or pauses it until the runner is cleared or ready and brings them back at half their week before (Moderate, Severe). A recovery made shorter still builds from the reduced week, not from the mileage before the injury. With heart rate on, easy and long runs say to ease off when heart rate stays over the easy ceiling for a minute.

On iPhone, a run with heart rate on also shows a Live Activity on the Lock Screen and in the Dynamic Island: the current heart rate (a dash once readings are more than 15 seconds old) and a graph of the last five minutes, with Pause and Resume buttons. The app updates it on the device, with no push server. When the run finishes, its final numbers stay on the Lock Screen for 15 minutes; a discarded run's goes at once. Runs recorded only on the watch don't get one yet.

## Project

Every chart shows the unit for each measured quantity on its axis, tick labels, or chart heading. Distance, pace, and elevation labels follow the runner’s unit setting.

- `WindRun.xcodeproj` with four targets:
  - `WindRun`: the iPhone app. It embeds the watch app and the Live Activity.
  - `WindRunWatch`: the Apple Watch app. It runs on its own with its own local store.
  - `WindRunLiveActivity`: the iPhone heart rate Live Activity. `LiveActivityShared/` holds what it and the app both compile.
  - `WindRunTests`: Swift Testing unit tests for the models.
- `Shared/` is compiled into both apps: SwiftData models, the GPS `RunRecorder`, pace call-outs, settings sync, formatting, the optional Apple Health sync (`HealthSync`), live heart rate (`HeartRateMonitor`), and first-open setup (`Shared/Prompts/`: one setup page, `FirstOpenSetup`, holds every first-open choice and asks Apple once for Health and once for Motion & Fitness; a new first-open choice goes on that page rather than adding a screen, and each device asks once).
- The iPhone app keeps recording and speaking with the phone locked (`audio` and `location` background modes in `WindRun/Info.plist`).
- If the system closes the app mid-run, the next launch on that device finishes that run at its last GPS fix or heart rate reading (`RunRecovery`), with its steps closed, so it shows in the list. Only the run this device was recording is touched, never one still recording on another device. A run that recorded nothing is deleted. Steps and barometer readings are saved every minute, so little is lost.
- Folders are file-system-synchronized, so new `.swift` files are picked up without editing the project file.
- `Branding/logo.svg` is the logo source. The app icons in both asset catalogs are 1024 px renders of it; the watch one is scaled to 86% so the paws and tail clear the round mask.
- SwiftUI and SwiftData only, no third-party dependencies. iOS 26 and watchOS 26. Code is main-actor isolated by default.

## Models

| Model | What it is |
| --- | --- |
| `Run` | One recorded run: kind (run, intervals, coach), status, distance and how it was measured, the straight-line sum, Apple's distance, the devices behind it, pauses, route, heart rate, barometer readings, calories. |
| `RouteSample` | One GPS fix: time, position, altitude, accuracy, speed and its accuracy, course. |
| `RunPause` | A stretch where the clock was paused. |
| `HeartRateSample` | One heart rate reading, taken while the run was active. |
| `IntervalPlan` → `IntervalBlock` → `IntervalStep` | A saved interval workout. A block repeats its steps, so "10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down" is three blocks. `timeline` writes out every step in order. |
| `CoachPlan` → `CoachWeek` → `CoachWorkout` | A Running Coach plan. The engine's state (`Shared/Coach/Engine/Build/`) is stored as JSON on the plan; the weeks and runs are a copy for the screens and for linking runs. |

Conventions follow PowerJack: stored properties end in `Value` and are read through accessors, ordered children carry an `order` and are returned sorted, and state changes go through guarded methods that log instead of throwing.

iCloud sync puts two more rules on every model: to-many relationships are optional (`[RouteSample]? = []`), and every relationship has an inverse. `SyncReadinessTests` fails if a model breaks either.

## Settings

Settings follows PowerJack's layout: the top page is one row per group, and each opens its own page (`WindRun/Features/Settings/`).

- **Personalization**: units, weight for calories, voice call-outs and haptics.
- **Health & Motion**: Save workouts to Health, heart rate, steps and cadence, and auto-pause.
- **Appearance**: System, Light or Dark.
- **Your Data**: iCloud Sync, Export Runs, and what stays private.
- **Legal**: the Privacy Policy and the Terms and Conditions.
- **Developer Tool**: trace logging, with "Trace On" on the row while it's on.

The watch keeps its single list of the settings it shares with the iPhone. For simulator screenshots, debug builds open Settings on a page with `-settingsDemo PAGE` (top, personalization, health, appearance, data, legal, privacy, terms or developer).

The privacy policy and terms are [`PRIVACY.md`](PRIVACY.md) and [`TERMS.md`](TERMS.md), and the app shows the same words from `LegalDocument` (`WindRun/Features/Settings/Legal/`). `LegalDocumentTests` fails if the two ever differ, so change both, and the date, together. Coach mode asks the runner to accept the terms before its first plan; when the terms change, bump `TermsAcceptance.currentVersion` and it asks again.

## iCloud sync

Settings → Your Data → iCloud Sync. It's off by default and needs the iPhone to be signed in to iCloud.

- `WindRunStore` (`WindRun/Persistence/`) owns the model container. Turning sync on or off swaps in a new container on the same store file, and the root view rebuilds its screens from it.
- Data goes to the runner's private CloudKit database in `iCloud.com.stanleycloud.WindRun`, in the zone SwiftData mirrors into.
- Turning sync on or off saves what's waiting first, and if the store can't be opened the new way it keeps the one it has and says so. Turning sync off asks first, closes the syncing container, then deletes that zone. If iCloud can't be reached, nothing is deleted and sync stays on. If the iPhone is signed out, or iCloud needs the password again or is restricted, Settings says which and the runner can turn sync off and leave the copy in iCloud.
- If the store can't be opened at launch, the app shows Couldn't Open Your Runs with Try Again instead of an empty store, and the reason goes to the trace. With iCloud Sync on, it first tries the store without sync, so the runs are still there.
- Settings sync too, through iCloud's key-value store (`CloudSettings`), only while iCloud Sync is on. Every key in `CloudSettings.keys` is copied under a `settings.` prefix. Turning sync on takes what's already in iCloud, so a new iPhone gets the old one's settings, and sends up anything iCloud doesn't have. A device syncing for the first time waits for iCloud's first download (up to 20 seconds) before sending its own, so its first-open answers don't beat the settings already there. After that each change goes both ways. Turning sync off deletes them with the runs. Which first-open prompts were answered, whether this device has had iCloud's settings yet, and the iCloud Sync switch itself stay on each device. A new setting stored in `UserDefaults` must be added to `CloudSettings.keys`.
- The watch records runs locally and syncs finished runs to the paired iPhone. With iCloud Sync on, the iPhone syncs them to the runner's private iCloud database. The watch's Recent Runs list shows the five latest runs and any older runs still waiting for the iPhone to confirm a save. Tap a run to see its summary. Settings such as units and call-outs merge between devices key by key.

Trying it in the simulator, where nobody is signed in to iCloud: run with `-fakeICloud signedIn`, `-fakeICloud signedOut` or `-fakeICloud unreachable` (debug builds only; both are in the `WindRun` scheme, turned off).

After the version check, tests, and watch build pass on `main`, CI uses the `CLOUDKIT_API_TOKEN` GitHub secret to add missing record types and fields from the tested models to CloudKit Development. It preserves existing fields, indexes, and permissions. If CI reports a schema conflict, inspect the Development schema in CloudKit Console before retrying.

CI compares Development with Production and reports the result in the run summary. Schema files stay on the runner.

Before merging `main` into `staging`, review any pending schema changes and select **Deploy Schema Changes** in [CloudKit Console](https://icloud.developer.apple.com/). TestFlight and App Store builds use the Production schema.

## Trace logging

Settings → Developer Tool → Trace logging, for reporting a problem. It's off by default, stays on each iPhone (it never syncs), and turning it on shows a warning first. While it's on, Settings says "Trace On" and every tap, screen, setting change, save, sync and sensor event goes into up to 10 files of 5 MB on the iPhone (`Shared/Trace/`), the oldest dropped first. Lines are timed in seconds since the app opened, on a clock that keeps counting while the iPhone sleeps, and if a file can't be written the trace backs off and marks how many lines were dropped. The files can be read, searched and deleted in the app, or shared as one zip. Turning it off deletes them, and asks first, with Export First, when there are any. Nothing in a trace says where or when the runner ran or who they are: no places, clock times, typed words, names, heart rates or weight, and errors are kept as their domain and code only.

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

## Releasing

Three long-lived branches, each feeding the next through a pull request. Every commit on `main` is built once, by Xcode Cloud, and that same build moves on to beta and the App Store, so a version and build number such as 0.2.0 (57) stay the same all the way.

| Branch | Takes pull requests from | On merge | Testers see |
| --- | --- | --- | --- |
| `main` | feature branches | Xcode Cloud builds, uploads and sends the build to the internal TestFlight group | alpha |
| `staging` | `main` only | the Beta workflow gives that build to the external TestFlight group and tags `vX.Y.Z-beta.N` | beta |
| `prod` | `staging` only | the App Store workflow submits that build for review, tags `vX.Y.Z` and opens the pull request that starts the next version | App Store |

The version lives in `Config/Version.xcconfig`; Xcode Cloud stamps the build number. [docs/RELEASING.md](docs/RELEASING.md) has the rules, the setup (secrets, variables, rulesets, TestFlight groups) and what to do when something fails.

After a model change, deploy the CloudKit schema to Production before promoting (see iCloud sync above). TestFlight and App Store builds use the Production environment.

