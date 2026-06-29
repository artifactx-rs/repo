#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)

publishable_roots=()
for dir in "$root/public" "$root/dist" "$root/work"; do
  if [ -e "$dir" ]; then
    publishable_roots+=("$dir")
  fi
done

if [ ${#publishable_roots[@]} -eq 0 ]; then
  printf 'No publishable artifact roots to scan.\n' >&2
  exit 1
fi

fail=0
private_key_marker='BEGIN PGP PRIVATE'
private_key_marker+=" KEY BLOCK"

if find "${publishable_roots[@]}" -type f -name 'private.asc' -print -quit | grep -q .; then
  printf 'private.asc found in publishable artifacts:\n' >&2
  find "${publishable_roots[@]}" -type f -name 'private.asc' -print >&2
  fail=1
fi

if grep -RIl --binary-files=without-match --exclude='*.deb' --exclude='*.rpm' \
  -- "$private_key_marker" "${publishable_roots[@]}" >/tmp/artifactx-private-key-grep.$$ 2>/dev/null; then
  printf 'PGP private key block found in publishable artifacts:\n' >&2
  cat /tmp/artifactx-private-key-grep.$$ >&2
  fail=1
fi
rm -f /tmp/artifactx-private-key-grep.$$

scan_deb_listing() {
  local pkg=$1
  if dpkg-deb -c "$pkg" | awk '{p=$6; sub("^\\./", "", p); print p}' \
    | grep -E '(^|/)private\.asc$|(^|/)repo/keys/' >/dev/null; then
    printf 'sensitive key path found inside deb package: %s\n' "$pkg" >&2
    fail=1
  fi
}

scan_rpm_listing() {
  local pkg=$1
  if rpm -qlp "$pkg" | grep -E '(^|/)private\.asc$|(^|/)repo/keys/' >/dev/null; then
    printf 'sensitive key path found inside rpm package: %s\n' "$pkg" >&2
    fail=1
  fi
}

if command -v dpkg-deb >/dev/null 2>&1; then
  while IFS= read -r -d '' pkg; do
    scan_deb_listing "$pkg"
  done < <(find "${publishable_roots[@]}" -type f -name '*.deb' -print0)
else
  printf 'Skipping deb payload listing scan: dpkg-deb not found.\n' >&2
fi

if command -v rpm >/dev/null 2>&1; then
  while IFS= read -r -d '' pkg; do
    scan_rpm_listing "$pkg"
  done < <(find "${publishable_roots[@]}" -type f -name '*.rpm' -print0)
else
  printf 'Skipping rpm payload listing scan: rpm not found.\n' >&2
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

printf 'Private key leak smoke passed for publishable artifacts: %s\n' "${publishable_roots[*]}"
