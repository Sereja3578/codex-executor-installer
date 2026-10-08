#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /absolute/path/to/private/codex-executor" >&2
  exit 2
fi

source_dir=$1
project_dir=$(cd "$(dirname "$0")/.." && pwd -P)
if [[ ! -d "$source_dir" || ! -f "$source_dir/server.py" || ! -f "$source_dir/install/portable.py" ]]; then
  echo "Private Executor source is missing or incomplete" >&2
  exit 2
fi

build_dir="$project_dir/.build"
dist_dir="$project_dir/dist"
mkdir -p "$build_dir" "$dist_dir"
stage_dir=$(mktemp -d "$build_dir/stage.XXXXXX")
trap 'rm -rf "$stage_dir"' EXIT
app_dir="$stage_dir/Codex Executor Installer.app"
contents_dir="$app_dir/Contents"
payload_dir="$contents_dir/Resources/Executor"
mkdir -p "$contents_dir/MacOS" "$payload_dir/install" "$payload_dir/ui"

for name in server.py codex_cli.py run_engine.py run_worker.py observer_engine.py observer_worker.py runtime_environment.py; do
  ditto --norsrc "$source_dir/$name" "$payload_dir/$name"
done
for name in launcher.py portable.py; do
  ditto --norsrc "$source_dir/install/$name" "$payload_dir/install/$name"
done
ditto --norsrc "$source_dir/ui" "$payload_dir/ui"

swiftc -parse-as-library -O -framework AppKit -framework Security \
  "$project_dir/Sources/Installer.swift" \
  -o "$contents_dir/MacOS/Codex Executor Installer"
ditto --norsrc "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"

source_commit=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || true)
if ! git -C "$source_dir" ls-files --error-unmatch server.py >/dev/null 2>&1; then
  source_commit=uncommitted
fi
printf '{"source_commit":"%s","payload_schema":1}\n' "$source_commit" > "$contents_dir/Resources/release.json"
(cd "$payload_dir" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$contents_dir/Resources/payload.sha256"

archive="$dist_dir/Codex Executor Installer.zip"
staged_archive="$stage_dir/Codex Executor Installer.zip"
ditto -c -k --norsrc --keepParent "$app_dir" "$staged_archive"
unzip -tq "$staged_archive" >/dev/null
mv -f "$staged_archive" "$archive"
echo "Built $archive"
echo "UNSIGNED development candidate. Do not distribute."
