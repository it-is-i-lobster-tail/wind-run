#!/bin/sh
# Downloads the offline US area pack into the iPhone app's resources, checked against its sha256.
#
# The pack (WindRun/OfflineAreas/Resources/USAreas.sqlite) is never committed. pack.json names the
# GitHub release that holds it. CI and Xcode Cloud run this before every build; run it once yourself
# before building locally. A build without the pack still works, but history search then asks Apple
# Maps about every workout's start.
set -eu

root=$(cd "$(dirname "$0")/../.." && pwd)
manifest="$root/scripts/offline_areas/pack.json"
target="$root/WindRun/OfflineAreas/Resources/USAreas.sqlite"
repository=${OFFLINE_AREAS_REPOSITORY:-it-is-i-lobster-tail/wind-run}

field() {
  sed -n "s/^ *\"$1\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}$/\1/p" "$manifest" | head -n 1
}

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d ' ' -f 1
  else sha256sum "$1" | cut -d ' ' -f 1
  fi
}

tag=$(field tag)
asset=$(field asset)
expected=$(field sha256)
if [ -z "$tag" ] || [ -z "$asset" ] || [ -z "$expected" ]; then
  echo "error: $manifest is missing tag, asset or sha256." >&2
  exit 1
fi

if [ -f "$target" ] && [ "$(sha256 "$target")" = "$expected" ]; then
  echo "The offline area pack from $tag is already in place."
  exit 0
fi

partial="$target.download"
trap 'rm -f "$partial"' EXIT
url="https://github.com/$repository/releases/download/$tag/$asset"
echo "Downloading $url"
curl --fail --location --silent --show-error --retry 4 --retry-delay 5 --output "$partial" "$url"
actual=$(sha256 "$partial")
if [ "$actual" != "$expected" ]; then
  echo "error: the downloaded pack's sha256 is $actual, but pack.json expects $expected." >&2
  exit 1
fi
mv "$partial" "$target"
echo "Saved the offline area pack from $tag."
