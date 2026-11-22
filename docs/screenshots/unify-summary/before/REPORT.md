# Run summary vs run detail: simulator comparison (before)

Build: origin/main at dfbe800, Debug, iPhone 18 Pro simulator (iOS 27.2), fresh install.
Setup: Imperial units, heart rate and Save to Health turned off on the welcome page, location granted.

Run: Free Run, simulated GPS at 3.5 m/s near Westminster, one pause (about 12 s), then Finish.
Totals: 0.43 mi, 3:27 moving, 0:12 paused, 215 fixes recorded (201 while running).

## Screenshots

| Screen | Top | Bottom |
| --- | --- | --- |
| Summary right after Finish | `summary-1.png` | `summary-2.png` |
| Same run from Run history | `detail-1.png` | `detail-2.png` |
| From history after relaunching the app | `relaunch-1.png` | (same as detail-2) |

## Summary counts (trace "Run summary built")

| Screen | fixes | routes | segments | pacePoints | cadencePoints | heartRatePoints | sections | hasElevation | hasCalories |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Run summary (after Finish) | 201 | 1 | 1 | 13 | 0 | 0 | 0 | no | yes |
| Run detail (from history) | 201 | 1 | 1 | 13 | 0 | 0 | 0 | no | yes |
| Run detail (after relaunch) | 201 | 1 | 1 | 13 | 0 | 0 | 0 | no | yes |

## Visible differences

The content is the same on all three screens: caption "Run", map and pace legend, Distance 0.43 mi,
Avg pace 7:56 /mi, Moving time 3:27 (Total 3:40), Time paused 0:12, Elevation –, Calories – with
"Add your weight in Settings", the Pace over time chart (same gap around the pause), and Recording details.

The only differences are the screen chrome:

- Summary: full-screen cover with a "Done" button at the top right and no back button. No tab bar.
- Detail: pushed on the Run tab, with a back button and a trash button. The floating tab bar
  sits over the bottom of the page (it becomes the small run and settings buttons once scrolled).

## What the simulator can't show

The simulator has no heart rate, no Motion & Fitness steps or cadence, no barometer and no Health
save, so those charts and stats were missing from both screens. A difference that comes from one of
them won't show up here. From the code (RunRecorder.finish, Shared/Recording/RunRecorder.swift:420),
the step counts, step log, barometer heights and calories are all written before `isShowingSummary`
is set (WindRun/Features/Run/ActiveRunView.swift:212), and heart rate and route samples arriving
after Finish are refused by `Run.record` once the run is finished. So with these sources the cached
`Summary` (WindRun/Features/Run/RunDetailView.swift:80) should be the same. The one thing that
changes after Finish is the Health save: it sets `healthWorkoutID` later
(Shared/Health/HealthSync.swift:208), which only adds the "Saved to Apple Health" line. That line reads the run directly, so it should
appear on the summary too once the save lands; only the cached `Summary` is fixed at first appearance.
