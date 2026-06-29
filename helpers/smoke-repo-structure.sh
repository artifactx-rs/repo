#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)

required=(
  "$root/repo/apt/dists/stable/InRelease"
  "$root/repo/apt/dists/stable/main/binary-amd64/Packages.gz"
  "$root/repo/yum/stable/x86_64/repodata/repomd.xml"
  "$root/public/apt/dists/stable/InRelease"
  "$root/public/apt/dists/stable/main/binary-amd64/Packages.gz"
  "$root/public/yum/stable/x86_64/repodata/repomd.xml"
  "$root/public/keys/public.asc"
)
for path in "${required[@]}"; do
  test -f "$path"
done
if [ -e "$root/public/keys/private.asc" ]; then
  printf 'private key leaked into public tree\n' >&2
  exit 1
fi
if find "$root/public" -name private.asc -print -quit | grep -q .; then
  printf 'private key leaked into public tree\n' >&2
  exit 1
fi

printf 'Repository structure smoke passed\n'
