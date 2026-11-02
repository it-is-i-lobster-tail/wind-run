#!/bin/sh
# Xcode Cloud runs this after each xcodebuild action. After an archive that is
# headed for TestFlight, it writes the "What to Test" notes testers see, from
# the latest commit messages. Xcode Cloud reads them from TestFlight/ next to
# the project:
# https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app
#
# The build number needs no script: Xcode Cloud stamps its own counter on
# every build. The version comes from Config/Version.xcconfig.
set -eu

if [ ! -d "${CI_APP_STORE_SIGNED_APP_PATH:-}" ]; then
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"
# Xcode Cloud clones only the latest commit; fetch a little more history.
git fetch --quiet --deepen 20 || true

mkdir -p TestFlight
{
  echo "Wind Run from ${CI_BRANCH:-main}, commit $(printf '%.7s' "$CI_COMMIT")."
  echo
  echo "Changes:"
  git log -n 10 --no-merges --pretty='- %s'
} | cut -c 1-300 | head -c 3900 > TestFlight/WhatToTest.en-US.txt

cat TestFlight/WhatToTest.en-US.txt
