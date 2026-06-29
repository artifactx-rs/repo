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

if [ -n "${ARCH:-}" ]; then
  arch_list="$ARCH"
else
  arch_list="${ARCHES:-amd64 arm64}"
fi

if [ "${CLEAN:-1}" = "1" ]; then
  rm -rf "$root/dist/$recipe"
  mkdir -p "$root/dist/$recipe"
fi

built_version=
for arch in $arch_list; do
  case "$arch" in
    amd64|arm64) ;;
    *) printf 'unsupported ARCH=%s; supported: amd64 arm64\n' "$arch" >&2; exit 1 ;;
  esac
  ARCH="$arch" "$recipe_dir/fetch.sh"
  ARCH="$arch" "$recipe_dir/render-manifest.sh"
  # shellcheck source=/dev/null
  . "$root/work/$recipe/current.env"
  built_version=$VERSION

  while IFS=$'\t' read -r package manifest_path; do
    [ -n "$package" ] || continue
    "$arx" pack "$manifest_path" --out "$root/dist/$recipe" --deb --rpm --source-date "${SOURCE_DATE_EPOCH:-0}"
    "$script_dir/smoke-package-structure.sh" "$recipe" "$VERSION" "$arch" "$package"
  done < "$MANIFESTS_FILE"
done

ensure_repo_root "$root" "$arx"
"$arx" add "$root/dist/$recipe" --root "$root/repo"
"$arx" publish --root "$root/repo" --strict --full
export_public_tree "$root"
"$script_dir/smoke-no-private-key-leak.sh"
ARCHES="$arch_list" "$script_dir/smoke-repo-structure.sh"

printf '\nBuilt package feed for %s %s (%s)\n' "$recipe" "$built_version" "$arch_list"
printf 'Packages: %s\n' "$root/dist/$recipe"
printf 'Private repo root: %s\n' "$root/repo"
printf 'Static public tree: %s\n' "$root/public"
