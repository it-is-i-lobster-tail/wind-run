#!/usr/bin/env bash
# Moves MARKETING_VERSION in Config/Version.xcconfig to the next version.
#
#   scripts/release/bump-version.sh minor    # 0.2.0 -> 0.3.0 (new features, the default after a release)
#   scripts/release/bump-version.sh patch    # 0.2.0 -> 0.2.1 (fixes only)
#   scripts/release/bump-version.sh major    # 0.2.0 -> 1.0.0 (first public release, redesign, one-way data change)
#   scripts/release/bump-version.sh 1.0.0    # an exact version, which must be higher
#
# Prints the new version. The release workflow runs it after a prod submission.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
xcconfig=Config/Version.xcconfig
part=${1:-minor}

current=$(sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\([0-9.]*\)[[:space:]]*$/\1/p' "$xcconfig")
if ! [[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Can't read MARKETING_VERSION from $xcconfig (found '$current')." >&2
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

case "$part" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  patch) next="$major.$minor.$((patch + 1))" ;;
  *)
    if ! [[ "$part" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
      echo "Give major, minor, patch or a version such as 1.0.0 (got '$part')." >&2
      exit 1
    fi
    if [ "$(printf '%s\n%s\n' "$current" "$part" | sort -V | tail -n 1)" != "$part" ] || [ "$part" = "$current" ]; then
      echo "$part is not higher than the current version $current." >&2
      exit 1
    fi
    next=$part
    ;;
esac

sed -i.bak "s/^\\([[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\\)$current[[:space:]]*\$/\\1$next/" "$xcconfig"
rm -f "$xcconfig.bak"
echo "$next"
