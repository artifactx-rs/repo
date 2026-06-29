#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)
recipe=${1:-victoriametrics}
recipe_dir="$root/recipes/$recipe"
recipe_file="$recipe_dir/recipe.toml"
repo_base=${REPO_BASE:-https://artifactx-rs.github.io/repo}
repo_base=${repo_base%/}

if [ ! -f "$recipe_file" ]; then
  printf 'Unknown recipe: %s\n' "$recipe" >&2
  exit 1
fi

emit_output() {
  local name=$1
  local value=$2
  printf '%s=%s\n' "$name" "$value"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT"
  fi
}

emit_notice() {
  local message=$1
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::notice::%s\n' "$message"
  else
    printf '%s\n' "$message"
  fi
}

if [ "${FORCE_BUILD:-0}" = "1" ]; then
  requested_version=${VERSION:-latest}
  emit_output latest_version "$requested_version"
  emit_output current_version ""
  emit_output should_build true
  emit_output reason manual-dispatch
  emit_notice "Manual dispatch requested; skipping version gate and running full refresh."
  exit 0
fi

upstream_project=$(
  python3 - <<'PY' "$recipe_file"
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
print(str(data.get('upstream', {}).get('project', '')).strip())
PY
)

if [ -z "$upstream_project" ]; then
  printf 'Recipe %s has no upstream.project in %s\n' "$recipe" "$recipe_file" >&2
  exit 1
fi

latest_url=$(
  curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$upstream_project/releases/latest"
)
latest_version=${latest_url##*/}
latest_version=${latest_version#v}
if [ -z "$latest_version" ] || [ "$latest_version" = latest ]; then
  printf 'Could not resolve latest upstream version from %s\n' "$latest_url" >&2
  exit 1
fi

current_version=
if packages_json=$(curl -fsSL "$repo_base/packages.json" 2>/dev/null); then
  current_version=$(
    PACKAGES_JSON="$packages_json" python3 - <<'PY'
import json, os
try:
    data = json.loads(os.environ['PACKAGES_JSON'])
except Exception:
    print('')
    raise SystemExit(0)
versions = []
for package in data.get('packages', []):
    version = str(package.get('version', '')).removeprefix('v')
    if version and version not in versions:
        versions.append(version)
print(versions[0] if versions else '')
PY
  )
else
  emit_notice "No deployed packages.json found at $repo_base/packages.json; treating next run as first publish."
fi

if [ -z "$current_version" ]; then
  should_build=true
  reason=no-current-version
elif [ "$latest_version" != "$current_version" ]; then
  should_build=true
  reason=latest-version-changed
else
  should_build=false
  reason=already-current
fi

emit_output latest_version "$latest_version"
emit_output current_version "$current_version"
emit_output should_build "$should_build"
emit_output reason "$reason"

if [ "$should_build" = true ]; then
  emit_notice "Upstream $upstream_project latest=$latest_version current=${current_version:-none}; running full refresh."
else
  emit_notice "Upstream $upstream_project latest=$latest_version already matches deployed version; skipping build/deploy/smoke."
fi
