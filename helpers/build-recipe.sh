#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)
recipe=${1:-victoriametrics}
recipe_dir="$root/recipes/$recipe"
if [ ! -d "$recipe_dir" ]; then
  printf 'Unknown recipe: %s\n' "$recipe" >&2
  exit 1
fi

arx=$(resolve_arx)
mkdir -p "$root/dist/$recipe" "$root/work/$recipe"

if [ "${CLEAN:-1}" = "1" ]; then
  rm -rf "$root/dist/$recipe"
  mkdir -p "$root/dist/$recipe"
fi

"$recipe_dir/fetch.sh"
"$recipe_dir/render-manifest.sh"
# shellcheck source=/dev/null
. "$root/work/$recipe/current.env"

"$arx" pack "$MANIFEST_PATH" --out "$root/dist/$recipe" --deb --rpm --source-date "${SOURCE_DATE_EPOCH:-0}"
"$script_dir/smoke-package-structure.sh" "$recipe" "$VERSION"

ensure_repo_root "$root" "$arx"
"$arx" add "$root/dist/$recipe" --root "$root/repo"
"$arx" publish --root "$root/repo" --strict --full
export_public_tree "$root"
"$script_dir/smoke-repo-structure.sh"

printf '\nBuilt package feed for %s %s\n' "$recipe" "$VERSION"
printf 'Packages: %s\n' "$root/dist/$recipe"
printf 'Private repo root: %s\n' "$root/repo"
printf 'Static public tree: %s\n' "$root/public"
