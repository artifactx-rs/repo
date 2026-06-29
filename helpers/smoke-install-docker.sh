#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=helpers/lib.sh
. "$script_dir/lib.sh"
root=$(repo_root)
recipe=${1:-victoriametrics}

if [ "$recipe" != victoriametrics ]; then
  printf 'No install smoke registered for recipe: %s\n' "$recipe" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is required for install smoke.\n' >&2
  exit 1
fi

test -d "$root/public"

docker run --rm --platform linux/amd64 -v "$root/public:/repo:ro" debian:bookworm-slim bash -euxo pipefail -c '
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates gpg
  install -d -m 0755 /usr/share/keyrings
  cp /repo/keys/public.asc /usr/share/keyrings/artifactx-packages.asc
  printf "%s\n" "deb [signed-by=/usr/share/keyrings/artifactx-packages.asc] file:/repo/apt stable main" > /etc/apt/sources.list.d/artifactx-packages.list
  apt-get update
  apt-get install -y --no-install-recommends victoriametrics
  test -x /usr/local/bin/victoria-metrics-prod
  /usr/local/bin/victoria-metrics-prod --version
  test -f /usr/lib/systemd/system/victoriametrics.service
'

docker run --rm --platform linux/amd64 -v "$root/public:/repo:ro" rockylinux:9 bash -euxo pipefail -c '
  cat > /etc/yum.repos.d/artifactx-packages.repo <<"REPO"
[artifactx-packages]
name=ArtifactX Packages
baseurl=file:///repo/yum/stable/$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=file:///repo/keys/public.asc
REPO
  dnf -y makecache
  dnf -y install victoriametrics
  test -x /usr/local/bin/victoria-metrics-prod
  /usr/local/bin/victoria-metrics-prod --version
  test -f /usr/lib/systemd/system/victoriametrics.service
'

printf 'Docker install smoke passed for %s\n' "$recipe"
