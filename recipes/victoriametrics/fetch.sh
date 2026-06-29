#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
recipe_file="$script_dir/recipe.toml"
components_file="$script_dir/components.tsv"
recipe_name=victoriametrics
arch=${ARCH:-amd64}
case "$arch" in
  amd64|arm64) ;;
  *)
    printf 'unsupported ARCH=%s; supported: amd64 arm64\n' "$arch" >&2
    exit 1
    ;;
esac
case "$arch" in
  amd64) rpm_arch=x86_64 ;;
  arm64) rpm_arch=aarch64 ;;
esac
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
  latest_url=$(
    curl -fsSLI -o /dev/null -w '%{url_effective}' \
      'https://github.com/VictoriaMetrics/VictoriaMetrics/releases/latest'
  )
  version=${latest_url##*/}
fi
version=${version#v}

base_url="https://github.com/VictoriaMetrics/VictoriaMetrics/releases/download/v${version}"
work_dir="$root/work/$recipe_name/$version/$arch"
download_dir="$work_dir/downloads"
extract_dir="$work_dir/extract"
stage_dir="$work_dir/stage"
mkdir -p "$download_dir" "$extract_dir" "$stage_dir"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

archive_name() {
  case "$1" in
    single) printf 'victoria-metrics-linux-%s-v%s.tar.gz\n' "$arch" "$version" ;;
    vmutils) printf 'vmutils-linux-%s-v%s.tar.gz\n' "$arch" "$version" ;;
    cluster) printf 'victoria-metrics-linux-%s-v%s-cluster.tar.gz\n' "$arch" "$version" ;;
    *) printf 'unknown archive kind: %s\n' "$1" >&2; return 1 ;;
  esac
}

checksum_name() {
  case "$1" in
    single) printf 'victoria-metrics-linux-%s-v%s_checksums.txt\n' "$arch" "$version" ;;
    vmutils) printf 'vmutils-linux-%s-v%s_checksums.txt\n' "$arch" "$version" ;;
    cluster) printf 'victoria-metrics-linux-%s-v%s-cluster_checksums.txt\n' "$arch" "$version" ;;
    *) printf 'unknown archive kind: %s\n' "$1" >&2; return 1 ;;
  esac
}

download_and_extract() {
  local kind=$1 archive checksums expected actual kind_extract
  archive=$(archive_name "$kind")
  checksums=$(checksum_name "$kind")
  curl -fL --retry 3 --retry-delay 2 -o "$download_dir/$archive" "$base_url/$archive"
  curl -fL --retry 3 --retry-delay 2 -o "$download_dir/$checksums" "$base_url/$checksums"

  expected=$(awk -v a="$archive" '$2 == a {print $1}' "$download_dir/$checksums")
  if [ -z "$expected" ]; then
    printf 'checksum for %s not found in %s\n' "$archive" "$checksums" >&2
    exit 1
  fi
  actual=$(sha256_of "$download_dir/$archive")
  if [ "$actual" != "$expected" ]; then
    printf 'sha256 mismatch for %s: %s != %s\n' "$archive" "$actual" "$expected" >&2
    exit 1
  fi
  printf '%s: OK\n' "$archive"

  kind_extract="$extract_dir/$kind"
  rm -rf "$kind_extract"
  mkdir -p "$kind_extract"
  tar -xzf "$download_dir/$archive" -C "$kind_extract"
  tar -tzf "$download_dir/$archive" > "$work_dir/archive-${kind}-contents.txt"
}

rm -rf "$extract_dir" "$stage_dir"
mkdir -p "$extract_dir" "$stage_dir"
for kind in single vmutils cluster; do
  download_and_extract "$kind"
done

provenance="$work_dir/provenance.txt"
{
  printf 'recipe=%s\nversion=%s\narch=%s\nbase_url=%s\n' "$recipe_name" "$version" "$arch" "$base_url"
  printf '\n[archives]\n'
  for kind in single vmutils cluster; do
    archive=$(archive_name "$kind")
    checksums=$(checksum_name "$kind")
    printf '%s_archive_url=%s/%s\n' "$kind" "$base_url" "$archive"
    printf '%s_checksum_url=%s/%s\n' "$kind" "$base_url" "$checksums"
    awk -v k="$kind" -v a="$archive" '$2 == a {printf "%s_archive_sha256=%s\n", k, $1}' "$download_dir/$checksums"
  done
  printf '\n[components]\n'
} > "$provenance"

tail -n +2 "$components_file" | while IFS=$'\t' read -r package binary archive_kind description service; do
  [ -n "$package" ] || continue
  binary_path=$(find "$extract_dir/$archive_kind" -type f -name "$binary" -print | head -n 1 || true)
  if [ -z "$binary_path" ]; then
    printf '%s not found in %s archive\n' "$binary" "$archive_kind" >&2
    exit 1
  fi
  package_stage="$stage_dir/$package"
  install -d -m 0755 "$package_stage/usr/local/bin"
  cp "$binary_path" "$package_stage/usr/local/bin/$binary"
  chmod 0755 "$package_stage/usr/local/bin/$binary"

  checksums=$(checksum_name "$archive_kind")
  expected=$(awk -v b="$binary" '$2 == b {print $1}' "$download_dir/$checksums")
  if [ -z "$expected" ]; then
    printf 'checksum for %s not found in %s\n' "$binary" "$checksums" >&2
    exit 1
  fi
  actual=$(sha256_of "$package_stage/usr/local/bin/$binary")
  if [ "$actual" != "$expected" ]; then
    printf 'sha256 mismatch for %s: %s != %s\n' "$binary" "$actual" "$expected" >&2
    exit 1
  fi

  if [ "$service" = yes ]; then
    install -d -m 0755 "$package_stage/usr/lib/systemd/system"
    service_path=$(find "$extract_dir/$archive_kind" -type f \( -name victoriametrics.service -o -name victoria-metrics.service \) -print | head -n 1 || true)
    service_source=release-archive
    if [ -z "$service_path" ]; then
      service_path="$script_dir/systemd/victoriametrics.service"
      service_source=official-docs-fallback
    fi
    cp "$service_path" "$package_stage/usr/lib/systemd/system/victoriametrics.service"
    chmod 0644 "$package_stage/usr/lib/systemd/system/victoriametrics.service"
  else
    service_source=none
  fi
  printf '%s\tbinary=%s\tarchive=%s\tsha256=%s\tservice_source=%s\tdescription=%s\n' \
    "$package" "$binary" "$archive_kind" "$actual" "$service_source" "$description" >> "$provenance"
done

cat > "$root/work/$recipe_name/current.env" <<EOF2
VERSION=$version
ARCH=$arch
DEB_ARCH=$arch
RPM_ARCH=$rpm_arch
WORK_DIR=$work_dir
STAGE_DIR=$stage_dir
MANIFEST_DIR=$work_dir/manifests
MANIFESTS_FILE=$work_dir/manifests.list
COMPONENTS_FILE=$components_file
EOF2

printf 'Fetched VictoriaMetrics %s (%s), staged %s components\n' "$version" "$arch" "$(($(wc -l < "$components_file") - 1))"
