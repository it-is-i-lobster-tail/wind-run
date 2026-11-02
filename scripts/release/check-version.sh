#!/usr/bin/env bash
# Checks the version setup Apple depends on. Runs in CI on every pull request
# (the "Version check" job) and locally from the repo root.
#
#   - Config/Version.xcconfig holds a valid MARKETING_VERSION: three whole
#     numbers, at most 18 characters, which is what App Store Connect accepts.
#   - CURRENT_PROJECT_VERSION there is the placeholder 1. Xcode Cloud stamps
#     the real build number; a committed number would only cause confusion.
#   - No target or Info.plist sets either value itself, so the app, the watch
#     app and the Live Activity always carry the same version and build.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
xcconfig=Config/Version.xcconfig
project=$(ls -d ./*.xcodeproj | head -n 1)/project.pbxproj
project=${project#./}
failed=0

fail() {
  echo "::error::$*"
  failed=1
}

setting() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\\([^[:space:]]*\\)[[:space:]]*\$/\\1/p" "$xcconfig"
}

version=$(setting MARKETING_VERSION)
build=$(setting CURRENT_PROJECT_VERSION)

if ! [[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "$xcconfig: MARKETING_VERSION '$version' must be MAJOR.MINOR.PATCH, three whole numbers such as 1.4.0."
elif (( ${#version} > 18 )); then
  fail "$xcconfig: MARKETING_VERSION '$version' is longer than the 18 characters App Store Connect allows."
fi

if [ "$build" != "1" ]; then
  fail "$xcconfig: CURRENT_PROJECT_VERSION must stay 1. Xcode Cloud stamps the real build number."
fi

if grep -nE '^[[:space:]]*(MARKETING_VERSION|CURRENT_PROJECT_VERSION) = ' "$project"; then
  fail "$project sets a version or build number on a target. Remove it so every target reads $xcconfig."
fi

references=$(grep -c 'baseConfigurationReference = [0-9A-F]* /\* Version.xcconfig \*/;' "$project" || true)
if [ "$references" -lt 2 ]; then
  fail "The project's Debug and Release configurations must both be based on $xcconfig (found $references)."
fi

while IFS= read -r plist; do
  if grep -A1 -E '<key>(CFBundleShortVersionString|CFBundleVersion)</key>' "$plist" | grep -E '<string>' | grep -vq '\$('; then
    fail "$plist hard-codes CFBundleShortVersionString or CFBundleVersion. Let Xcode generate them from the build settings."
  fi
done < <(git ls-files '*.plist')

if [ "$failed" -ne 0 ]; then
  exit 1
fi
echo "Version $version, build number stamped at upload. Every target reads $xcconfig."
