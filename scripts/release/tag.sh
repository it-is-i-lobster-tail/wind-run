#!/usr/bin/env bash
# Points a tag at a commit through the GitHub API, which needs no git credentials.
#
#   scripts/release/tag.sh TAG COMMIT [--move]
#
# Run again with the same commit, it does nothing. If the tag already marks a
# different commit it fails, unless --move is given (used for a version that
# was resubmitted with a new build before Apple approved it).
# Needs GH_TOKEN and GITHUB_REPOSITORY, as GitHub Actions provides.
set -euo pipefail

tag=$1
sha=$2
move=${3:-}
repo=${GITHUB_REPOSITORY:?}

current=$(gh api "repos/$repo/git/ref/tags/$tag" --jq '.object.sha' 2>/dev/null || true)
if [ -z "$current" ]; then
  gh api "repos/$repo/git/refs" -f "ref=refs/tags/$tag" -f "sha=$sha" --silent
  echo "Tagged ${sha:0:7} as $tag."
elif [ "$current" = "$sha" ]; then
  echo "$tag already marks ${sha:0:7}."
elif [ "$move" = "--move" ]; then
  gh api -X PATCH "repos/$repo/git/refs/tags/$tag" -f "sha=$sha" -F force=true --silent
  echo "Moved $tag from ${current:0:7} to ${sha:0:7}."
else
  echo "::error::$tag already marks ${current:0:7}, not ${sha:0:7}. A tag names one build; this should not happen for a new build number."
  exit 1
fi
