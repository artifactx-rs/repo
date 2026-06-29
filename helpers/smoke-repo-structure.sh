#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)

if [ -n "${ARCH:-}" ]; then
  arch_list="$ARCH"
else
  arch_list="${ARCHES:-amd64 arm64}"
fi

required=(
  "$root/repo/apt/dists/stable/InRelease"
  "$root/public/apt/dists/stable/InRelease"
  "$root/public/keys/public.asc"
)
for arch in $arch_list; do
  case "$arch" in
    amd64) deb_arch=amd64; rpm_arch=x86_64 ;;
    arm64) deb_arch=arm64; rpm_arch=aarch64 ;;
    *) printf 'unsupported ARCH=%s; supported: amd64 arm64\n' "$arch" >&2; exit 1 ;;
  esac
  required+=(
    "$root/repo/apt/dists/stable/main/binary-${deb_arch}/Packages.gz"
    "$root/repo/yum/stable/${rpm_arch}/repodata/repomd.xml"
    "$root/public/apt/dists/stable/main/binary-${deb_arch}/Packages.gz"
    "$root/public/yum/stable/${rpm_arch}/repodata/repomd.xml"
  )
done
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
