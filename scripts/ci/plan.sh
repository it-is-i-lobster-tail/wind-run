#!/usr/bin/env bash
# Decides whether the "Build and test" job needs a macOS runner. Runs in the
# "Plan" job of ci.yml and writes full=true|false to $GITHUB_OUTPUT.
#
# The macOS job is skipped (GitHub reports a skipped job as passing) only when
# testing again can't tell us anything new:
#   - A pull request that changes only documentation (see is_doc).
#   - A pull request (main -> staging, staging -> prod) whose merged tree is
#     exactly a tree CI already passed on a push to main. If that main run is
#     still going, this waits for it.
# Pushes to main and manual runs always run the full job.
#
# Needs: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME, GITHUB_SHA,
# PR_NUMBER, PR_HEAD_SHA, BASE_REF. The checkout needs depth 2 so the merge
# commit's tree is readable.
set -euo pipefail

decide() {
  echo "full=$1" >> "$GITHUB_OUTPUT"
  echo "$2" | tee -a "$GITHUB_STEP_SUMMARY"
  exit 0
}

[[ "$GITHUB_EVENT_NAME" == "pull_request" ]] || decide true "Full build: $GITHUB_EVENT_NAME runs always build and test."

# Paths that never reach the app, its tests or the CI scripts. PRIVACY.md and
# TERMS.md ship in the app (LegalDocumentTests), so they are not docs here.
is_doc() {
  case "$1" in
    docs/*|research/*|.github/rulesets/*|README.md|CLAUDE.md|AGENTS.md) return 0 ;;
    *) return 1 ;;
  esac
}

files=$(gh api --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/files" --jq '.[] | .filename, (.previous_filename // empty)')
code_change=false
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if ! is_doc "$file"; then code_change=true; break; fi
done <<< "$files"
if [[ "$code_change" == false && -n "$files" ]]; then
  decide false "Skipped the macOS build: this pull request changes only documentation."
fi

# Promotion pull requests: the merge result usually has main's exact tree.
if [[ "$BASE_REF" == "staging" || "$BASE_REF" == "prod" ]]; then
  merge_tree=$(git rev-parse "$GITHUB_SHA^{tree}")
  head_tree=$(git rev-parse "$PR_HEAD_SHA^{tree}")
  if [[ "$merge_tree" != "$head_tree" ]]; then
    decide true "Full build: merging into $BASE_REF gives a tree that differs from the source branch."
  fi
  # Reuse only a main push run for this exact head commit. A staging -> prod
  # head is a staging merge commit that never ran on main, so it builds in full.
  deadline=$((SECONDS + 70 * 60))
  while :; do
    runs=$(gh api "repos/$GITHUB_REPOSITORY/actions/workflows/ci.yml/runs?event=push&branch=main&head_sha=$PR_HEAD_SHA&per_page=20" \
      --jq '[.workflow_runs[] | {status, conclusion}]')
    if [[ $(jq '[.[] | select(.conclusion == "success")] | length' <<< "$runs") -gt 0 ]]; then
      decide false "Skipped the macOS build: CI already passed on main for $PR_HEAD_SHA, and the merge into $BASE_REF has the same files."
    fi
    if [[ $(jq '[.[] | select(.status != "completed")] | length' <<< "$runs") -eq 0 ]]; then
      decide true "Full build: no passing main run for $PR_HEAD_SHA."
    fi
    if (( SECONDS > deadline )); then
      decide true "Full build: the main run for $PR_HEAD_SHA did not finish in time."
    fi
    echo "Waiting for the main run of $PR_HEAD_SHA to finish..."
    sleep 60
  done
fi

decide true "Full build: this pull request changes code."
