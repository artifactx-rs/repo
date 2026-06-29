#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)
recipe=${1:-victoriametrics}
components_file="$root/recipes/$recipe/components.tsv"
repo_base=${REPO_BASE:-https://artifactx-rs.github.io/repo}
repo_base=${repo_base%/}

if [ ! -f "$components_file" ]; then
  printf 'No live install smoke registered for recipe: %s\n' "$recipe" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is required for live install smoke.\n' >&2
  exit 1
fi

packages=$(awk -F '\t' 'NR > 1 {printf "%s%s", sep, $1; sep=" "}' "$components_file")
binaries=$(awk -F '\t' 'NR > 1 {printf "%s%s", sep, $2; sep=" "}' "$components_file")

if [ -n "${ARCH:-}" ]; then
  arch_list="$ARCH"
else
  arch_list="${ARCHES:-amd64 arm64}"
fi

printf 'Live repository base: %s\n' "$repo_base"
printf 'Packages under test: %s\n' "$packages"

for arch in $arch_list; do
  case "$arch" in
    amd64) platform=linux/amd64 ;;
    arm64) platform=linux/arm64 ;;
    *) printf 'unsupported ARCH=%s; supported: amd64 arm64\n' "$arch" >&2; exit 1 ;;
  esac

  printf '\n== Debian live install smoke (%s) ==\n' "$platform"
  docker run --rm --platform "$platform" \
    -e PACKAGES="$packages" -e BINARIES="$binaries" -e REPO_BASE="$repo_base" \
    debian:bookworm-slim bash -euxo pipefail -c '
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl gpg
    curl -fsSL "$REPO_BASE/install.sh" | bash
    grep -F "${REPO_BASE}/apt stable main" /etc/apt/sources.list.d/artifactx-packages.list
    apt-get install -y --no-install-recommends $PACKAGES
    for bin in $BINARIES; do
      test -x "/usr/local/bin/$bin"
      "/usr/local/bin/$bin" --version || "/usr/local/bin/$bin" -version || "/usr/local/bin/$bin" -help >/dev/null
    done
    test -f /usr/lib/systemd/system/victoriametrics.service
  '

  printf '\n== Rocky Linux live install smoke (%s) ==\n' "$platform"
  docker run --rm --platform "$platform" \
    -e PACKAGES="$packages" -e BINARIES="$binaries" -e REPO_BASE="$repo_base" \
    rockylinux:9 bash -euxo pipefail -c '
    curl -fsSL "$REPO_BASE/install.sh" | bash
    grep -F "baseurl=${REPO_BASE}/yum/stable/" /etc/yum.repos.d/artifactx-packages.repo
    dnf -y install $PACKAGES
    for bin in $BINARIES; do
      test -x "/usr/local/bin/$bin"
      "/usr/local/bin/$bin" --version || "/usr/local/bin/$bin" -version || "/usr/local/bin/$bin" -help >/dev/null
    done
    test -f /usr/lib/systemd/system/victoriametrics.service
  '
done

printf 'Live Docker install smoke passed for %s (%s) from %s\n' "$recipe" "$arch_list" "$repo_base"
