#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)
recipe=${1:?recipe required}
version=${2:?version required}
arch=${3:-amd64}
case "$arch" in
  amd64) deb_arch=amd64; rpm_arch=x86_64 ;;
  arm64) deb_arch=arm64; rpm_arch=aarch64 ;;
  *)
    printf 'unsupported arch for smoke: %s\n' "$arch" >&2
    exit 1
    ;;
esac

case "$recipe" in
  victoriametrics)
    pkg=victoriametrics
    files=(/usr/local/bin/victoria-metrics-prod /usr/lib/systemd/system/victoriametrics.service)
    ;;
  *)
    printf 'No structure smoke registered for recipe: %s\n' "$recipe" >&2
    exit 1
    ;;
esac

dist="$root/dist/$recipe"
deb="$dist/${pkg}_${version}_${deb_arch}.deb"
rpm="$dist/${pkg}-${version}-1.${rpm_arch}.rpm"

test -f "$deb"
test -f "$rpm"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  printf 'dpkg-deb is required for package smoke checks.\n' >&2
  exit 1
fi
if ! command -v rpm >/dev/null 2>&1; then
  printf 'rpm is required for package smoke checks.\n' >&2
  exit 1
fi

[ "$(dpkg-deb -f "$deb" Package)" = "$pkg" ]
[ "$(dpkg-deb -f "$deb" Version)" = "$version" ]
[ "$(dpkg-deb -f "$deb" Architecture)" = "$deb_arch" ]
for path in "${files[@]}"; do
  dpkg-deb -c "$deb" | awk '{p=$6; sub("^\\./", "", p); if (p !~ "^/") p="/" p; print p}' | grep -Fx -- "$path" >/dev/null
done

rpm_name=$(rpm -qp --qf '%{NAME}' "$rpm")
rpm_version=$(rpm -qp --qf '%{VERSION}' "$rpm")
rpm_release=$(rpm -qp --qf '%{RELEASE}' "$rpm")
rpm_pkg_arch=$(rpm -qp --qf '%{ARCH}' "$rpm")
[ "$rpm_name" = "$pkg" ]
[ "$rpm_version" = "$version" ]
[ "$rpm_release" = "1" ]
[ "$rpm_pkg_arch" = "$rpm_arch" ]
for path in "${files[@]}"; do
  rpm -qlp "$rpm" | grep -Fx -- "$path" >/dev/null
done

printf 'Package structure smoke passed for %s %s (%s)\n' "$pkg" "$version" "$arch"
