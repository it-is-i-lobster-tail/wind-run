#!/usr/bin/env bash
set -euo pipefail
fresh=$1
target=WindRun/OfflineAreas/Resources
# SQLite page layouts vary across hosts. Compare full feature content, and
# verify the shipped files against their own manifest before promoting them.
python3 - "$target" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for shard in json.loads((root / "USAreas.json").read_text())["shards"]:
    with (root / shard["file"]).open("rb") as file:
        if hashlib.file_digest(file, "sha256").hexdigest() != shard["sha256"]:
            raise SystemExit("Bundled US boundary shard has an invalid checksum")
PY
metadata() { jq -cS '{format,release,digest,counts}' "$1/USAreas.json"; }
if [[ "$(metadata "$target")" == "$(metadata "$fresh")" ]]; then
  echo "The main archive includes the current US boundary data."
  exit 0
fi
release=$(jq -r '.release' "$fresh/USAreas.json")
digest=$(jq -r '.digest' "$fresh/USAreas.json")
branch="codex/us-boundaries-${digest:0:16}-$(git rev-parse --short HEAD)"
if ! git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  git switch -c "$branch"
  git rm -- "$target"/USAreas-*.sqlite
  cp "$fresh"/USAreas* "$target/"
  git add -- "$target"
  git -c user.name=github-actions -c user.email=41898282+github-actions[bot]@users.noreply.github.com commit -m "Refresh US offline areas for $release"
  git push origin "HEAD:$branch"
fi
if [[ -z "$(gh pr list --base main --head "$branch" --json number --jq '.[0].number // empty')" ]]; then
  gh pr create --base main --head "$branch" --title "Refresh US offline boundaries for $release" \
    --body "The staging data check downloaded and packaged Overture release $release. Merge this update into main to include the refreshed boundaries in the signed beta build."
fi
echo "::error::Merge the US boundary refresh into main before promoting it to staging."
exit 1
