#!/bin/sh
# Xcode Cloud runs this before each xcodebuild action. Before an archive, it
# stamps the build's version into Config/Version.xcconfig, so every build from
# main carries its own version: 1.1.0, 1.1.1, 1.1.2... The committed file keeps
# the version the line starts at; scripts/release/build-version.sh explains
# the count.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"
version=$(scripts/release/build-version.sh HEAD)
sed -i '' "s/^\([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\).*\$/\1$version/" Config/Version.xcconfig
echo "Version $version for commit $(git rev-parse --short HEAD)."
grep MARKETING_VERSION Config/Version.xcconfig
