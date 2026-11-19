#!/usr/bin/env bash
# Prints the version a main commit's build carries, such as 1.1.4.
#
#   scripts/release/build-version.sh [commit]
#
# Config/Version.xcconfig holds the version a line starts at (1.1.0). Every
# commit on main after the one that set it adds one to the patch number, so
# each build Xcode Cloud makes from main has a version of its own:
#
#   merge that sets 1.1.0  -> 1.1.0
#   next merge into main   -> 1.1.1
#   the one after          -> 1.1.2
#
# Only main's own line of commits counts (--first-parent): a pull request
# with ten commits still moves the patch by one when it merges. Changing
# MARKETING_VERSION (the "Start version" pull request after a release, or by
# hand) starts the count again from the new number.
#
# Needs the history back to that change; on a shallow clone it fetches it.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
xcconfig=Config/Version.xcconfig
commit=$(git rev-parse --verify "${1:-HEAD}^{commit}")

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  git fetch --quiet --unshallow >&2 || git fetch --quiet --deepen 2000 >&2 || true
fi

base_version=$(git show "$commit:$xcconfig" | sed -n 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*\([0-9.]*\)[[:space:]]*$/\1/p')
if ! [[ "$base_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Can't read MARKETING_VERSION from $xcconfig at ${commit:0:7} (found '$base_version')." >&2
  exit 1
fi
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

# The newest commit on main's line that changed the MARKETING_VERSION line.
set_at=$(git log -1 --format=%H --no-patch --first-parent --diff-merges=first-parent \
  -G '^[[:space:]]*MARKETING_VERSION[[:space:]]*=' "$commit" -- "$xcconfig")
if [ -z "$set_at" ]; then
  echo "Can't find the commit that set MARKETING_VERSION $base_version; the clone's history is too short." >&2
  exit 1
fi

since=$(git rev-list --count --first-parent "$set_at..$commit")
echo "$major.$minor.$((patch + since))"
