# Releasing Wind Run

Every commit on `main` is built once, by Xcode Cloud. Beta and the App Store get that same build, never a rebuild, so what testers checked is exactly what ships. Every build from `main` has a version of its own, such as **1.1.4 (57)**, which names it from alpha to release.

| Branch | Channel | What happens on a push | Git record |
| --- | --- | --- | --- |
| `main` | Alpha: internal TestFlight group | Xcode Cloud archives, stamps the next build number, uploads, and sends the build to the internal group | none; Xcode Cloud links the commit to the build |
| `staging` | Beta: external TestFlight group | The **Beta** workflow finds the build made from the merged `main` commit and gives it to the external group | tag `v0.2.0-beta.57` |
| `prod` | App Store | The **App Store** workflow submits that build for review, then opens a pull request that moves `main` to the next version | tag `v0.2.0` and a GitHub Release |

## Version and build number

Apple reads two numbers from every build, and rejects an upload whose pair it has seen before:

| Info.plist key | Build setting | Where it comes from |
| --- | --- | --- |
| `CFBundleShortVersionString`, the version people see | `MARKETING_VERSION` | `Config/Version.xcconfig` holds where the line starts (1.1.0); Xcode Cloud stamps the patch at build time |
| `CFBundleVersion`, the build number | `CURRENT_PROJECT_VERSION` | Xcode Cloud's counter, stamped at build time; the file keeps a placeholder `1` |

- Every target (app, watch app, Live Activity, tests) reads both from `Config/Version.xcconfig`, the base configuration of the project. No target sets them, because Apple requires the watch app and extensions to match the app.
- The version is `MAJOR.MINOR.PATCH`, digits only. Apple allows no letters, so "alpha" and "beta" are TestFlight groups and tags, not part of the version.
- Build numbers come from one counter and only go up, across every version.
- `scripts/release/check-version.sh` checks all of this. CI runs it on every pull request as the **Version check** job.

### The patch counts every merge

The patch number moves by itself. Before archiving, `ci_scripts/ci_pre_xcodebuild.sh` runs `scripts/release/build-version.sh`, which adds one to the committed patch for every commit on `main`'s own line (merges, not the commits inside a pull request) since `MARKETING_VERSION` last changed, and stamps the result into the build:

| Commit on `main` | Version |
| --- | --- |
| The merge that set `MARKETING_VERSION = 1.1.0` | 1.1.0 |
| The next merge | 1.1.1 |
| The one after | 1.1.2 |

So the version alone says which build someone has, and a beta or release never reuses a version Apple has seen. `scripts/release/build-version.sh <commit>` prints the version of any commit's build; the beta and release tags (`v1.1.4-beta.57`, `v1.1.4`) record it too. The committed file keeps the line's starting version, and a local Xcode build shows that starting version.

### Which number to raise by hand

- **Minor** (1.1.x → 1.2.0) after a release, or for a release with new features. The automatic pull request after an App Store submission does this.
- **Major** (1.x → 2.0.0) for a redesign, a one-way data change or a dropped OS version.
- **Patch**: never by hand; it counts merges.

`scripts/release/bump-version.sh minor|major|X.Y.Z` makes the change, and the count starts again from the new number.

## Day to day

**Alpha.** Merge to `main`. Internal testers get the build when Xcode Cloud finishes. The notes they see list the latest commits (`ci_scripts/ci_post_xcodebuild.sh`).

**Beta.** Open a pull request from `main` into `staging` and merge it. The Beta workflow waits (up to an hour) for Xcode Cloud to finish that commit's build and for App Store Connect to process it, then adds it to the external group with the commits since the last beta as its notes. Every beta is a new version, so each goes through Beta App Review (usually quick after the first) before external testers get it.

**Release.** Fill in the version's App Store details in App Store Connect (What's New for every update; screenshots, description and privacy answers the first time), then open a pull request from `staging` into `prod` and merge it. The App Store workflow checks the version is higher than anything Apple has approved, submits the build for review, tags it and writes the GitHub Release. Approved versions release by themselves unless `APP_STORE_AUTOMATIC_RELEASE` is `false`.

**Next version.** Right after the submission, the App Store workflow opens a "Start version X.Y.0" pull request on `main` that moves to the next minor line. Builds from `main` keep working before it merges, since every merge already gets a new patch; merge it when you want the minor number to move. Change the number on that branch first if the next release is a major.

**Rejected by App Review.** Fix it on `main` and promote again. The fix's build has the next patch, so the App Store workflow renames the rejected version in App Store Connect to it.

**A failed promotion.** Re-run it from the Actions tab once the cause is fixed. The messages mean:

| Message | What to do |
| --- | --- |
| has changes that main never built | Something landed on `staging` or `prod` that isn't on `main`. Promote only by merging `main` into `staging` and `staging` into `prod`. |
| Xcode Cloud hasn't started a build | The Xcode Cloud workflow didn't run for that commit. Start it in Xcode Cloud, then re-run. |
| ended failed | Xcode Cloud's build failed. Fix `main` and promote the next commit. |
| has expired in TestFlight | TestFlight builds last 90 days. Push to `main` for a fresh build. |
| is not higher than … which Apple already approved | Promote a newer build from `main`. |
| says X, but … should be Y | Xcode Cloud didn't stamp the version. Check `ci_scripts/ci_pre_xcodebuild.sh` ran in that build's log. |

## Setting it up

Once, in App Store Connect:

1. **Xcode Cloud workflow** for the `WindRun` scheme: start condition *Branch changes* on `main`; action *Archive*, iOS, deployment preparation *TestFlight and App Store* (an *Internal Testing Only* build can't go to external testers or the App Store); post-action *TestFlight Internal Testing* to the internal group. Its tests can stay off: GitHub runs them.
2. **Build numbers:** if App Store Connect already holds builds that Xcode Cloud didn't make, set Xcode Cloud's next build number above the highest one (App Store Connect → Xcode Cloud → Settings → Build Number).
3. **TestFlight groups:** an internal group for alpha and an external group named `Beta` (or set `TESTFLIGHT_BETA_GROUPS`). Fill in TestFlight → Test Information, which Beta App Review needs.
4. **API key:** Users and Access → Integrations → App Store Connect API → Team Keys, with the App Manager role.

Once, in GitHub (Settings → Secrets and variables → Actions, or the `testflight` and `app-store` environments):

| Secret | What it is |
| --- | --- |
| `ASC_KEY_ID` | The API key's ID |
| `ASC_ISSUER_ID` | The issuer ID shown above the key list |
| `ASC_KEY_P8_BASE64` | The key's `.p8` file, base64: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `RELEASE_PR_TOKEN` | Optional. A fine-grained token with Contents and Pull requests write access to this repository. Pull requests opened with the default token don't start the required checks; without this one, close and reopen the "Start version" pull request to start them. |

| Variable | What it is |
| --- | --- |
| `TESTFLIGHT_BETA_GROUPS` | External group names, comma-separated. `Beta` if unset. |
| `APP_STORE_AUTOMATIC_RELEASE` | `false` to hold an approved version until it's released by hand. |

Also turn on Settings → Actions → General → *Allow GitHub Actions to create and approve pull requests*, so the App Store workflow can open the "Start version" pull request.

**Merge rules.** The rulesets in `.github/rulesets/` require a pull request, merge commits only, and the `Build and test`, `Version check` and `Source branch` checks. Import each in Settings → Rules → Rulesets → New ruleset → Import a ruleset. Once Xcode Cloud has reported on a commit, add its check too (the name shows on the commit), so a commit whose build failed can't be promoted.

**Staging and prod must descend from `main`.** Promotions walk merge commits back to a `main` commit, so both branches have to be cut from `main`'s current history before the first promotion.

## Using this in another app

The pieces are app-agnostic apart from a few names:

- `Config/Version.xcconfig`, set as the project's base configuration for every build configuration, with no `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` left on any target.
- `scripts/release/` as is. `check-version.sh` uses the first `.xcodeproj` it finds.
- `ci_scripts/ci_pre_xcodebuild.sh` as is, for the per-merge patch number.
- `fastlane/Fastfile` and `fastlane/app_store_connect.rb`: change `APP_IDENTIFIER`.
- `ci_scripts/ci_post_xcodebuild.sh`: change the app name in the first line of the notes.
- `.github/workflows/promote-beta.yml`, `promote-release.yml`, `promotion-guard.yml`, and the Version check job in `ci.yml`.
