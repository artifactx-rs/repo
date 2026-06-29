#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
recipe_file="$script_dir/recipe.toml"
recipe_name=victoriametrics
arch=${ARCH:-amd64}
version=${VERSION:-}
if [ -z "$version" ]; then
  version=$(python3 - <<'PY' "$recipe_file"
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
print(str(data['package']['version']).removeprefix('v'))
PY
)
fi
if [ "$version" = latest ]; then
  version=$(python3 - <<'PY'
import json, urllib.request
url = 'https://api.github.com/repos/VictoriaMetrics/VictoriaMetrics/releases/latest'
with urllib.request.urlopen(url, timeout=30) as r:
    data = json.load(r)
print(str(data['tag_name']).removeprefix('v'))
PY
)
fi
version=${version#v}

archive="victoria-metrics-linux-${arch}-v${version}.tar.gz"
checksums="victoria-metrics-linux-${arch}-v${version}_checksums.txt"
base_url="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${version}"
work_dir="$root/work/$recipe_name/$version"
download_dir="$work_dir/downloads"
extract_dir="$work_dir/extract"
stage_dir="$work_dir/stage"
mkdir -p "$download_dir" "$extract_dir" "$stage_dir/usr/local/bin" "$stage_dir/usr/lib/systemd/system"

curl -fL --retry 3 --retry-delay 2 -o "$download_dir/$archive" "$base_url/$archive"
curl -fL --retry 3 --retry-delay 2 -o "$download_dir/$checksums" "$base_url/$checksums"

(
  cd "$download_dir"
  grep "  ${archive}$" "$checksums" > "$archive.sha256"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$archive.sha256"
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c "$archive.sha256"
  else
    python3 - <<'PY' "$archive" "$archive.sha256"
import hashlib, pathlib, sys
archive = pathlib.Path(sys.argv[1])
expected = pathlib.Path(sys.argv[2]).read_text().split()[0]
actual = hashlib.sha256(archive.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f'sha256 mismatch: {actual} != {expected}')
print(f'{archive}: OK')
PY
  fi
)

rm -rf "$extract_dir"
mkdir -p "$extract_dir"
tar -xzf "$download_dir/$archive" -C "$extract_dir"
tar -tzf "$download_dir/$archive" > "$work_dir/archive-contents.txt"

binary_path=$(find "$extract_dir" -type f -name victoria-metrics-prod -print | head -n 1 || true)
if [ -z "$binary_path" ]; then
  printf 'victoria-metrics-prod not found in %s\n' "$archive" >&2
  exit 1
fi
cp "$binary_path" "$stage_dir/usr/local/bin/victoria-metrics-prod"
chmod 0755 "$stage_dir/usr/local/bin/victoria-metrics-prod"

service_path=$(find "$extract_dir" -type f \( -name victoriametrics.service -o -name victoria-metrics.service \) -print | head -n 1 || true)
service_source=release-archive
if [ -z "$service_path" ]; then
  service_path="$script_dir/systemd/victoriametrics.service"
  service_source=official-docs-fallback
fi
cp "$service_path" "$stage_dir/usr/lib/systemd/system/victoriametrics.service"
chmod 0644 "$stage_dir/usr/lib/systemd/system/victoriametrics.service"

archive_sha256=$(awk -v a="$archive" '$2 == a {print $1}' "$download_dir/$checksums")
binary_sha256=$(awk '$2 == "victoria-metrics-prod" {print $1}' "$download_dir/$checksums" || true)
cat > "$work_dir/provenance.txt" <<EOF2
recipe=$recipe_name
version=$version
arch=$arch
archive_url=$base_url/$archive
checksum_url=$base_url/$checksums
archive_sha256=$archive_sha256
binary_sha256=$binary_sha256
service_source=$service_source
official_docs=https://docs.victoriametrics.com/victoriametrics/quick-start/
EOF2

cat > "$root/work/$recipe_name/current.env" <<EOF2
VERSION=$version
WORK_DIR=$work_dir
STAGE_DIR=$stage_dir
BINARY_PATH=$stage_dir/usr/local/bin/victoria-metrics-prod
SERVICE_PATH=$stage_dir/usr/lib/systemd/system/victoriametrics.service
MANIFEST_PATH=$work_dir/arx-pack.toml
EOF2

printf 'Fetched VictoriaMetrics %s (%s), service_source=%s\n' "$version" "$arch" "$service_source"
