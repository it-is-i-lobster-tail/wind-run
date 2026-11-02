#!/usr/bin/env bash
# Prints the main commit whose Xcode Cloud build a staging or prod push should promote.
#
#   scripts/release/built-commit.sh [commit] [main-ref]
#
# Promotions are merge commits: staging merges main, prod merges staging. This
# walks from the pushed commit through each merge's incoming side, as long as
# the files are identical, and stops at a commit that is on main. If staging or
# prod holds any change that main never built, it fails instead of shipping an
# untested build.
set -euo pipefail

commit=$(git rev-parse --verify "${1:-HEAD}^{commit}")
main_ref=${2:-origin/main}
start=$commit

while git rev-parse --verify --quiet "$commit^2" >/dev/null; do
  incoming=$(git rev-parse "$commit^2")
  if [ "$(git rev-parse "$commit^{tree}")" != "$(git rev-parse "$incoming^{tree}")" ]; then
    break
  fi
  commit=$incoming
done

if ! git merge-base --is-ancestor "$commit" "$main_ref"; then
  {
    echo "::error::${start:0:7} has changes that main never built, so there is no build to promote."
    echo "Promote by merging main into staging, and staging into prod, with nothing else in the merge."
  } >&2
  exit 1
fi

echo "$commit"
