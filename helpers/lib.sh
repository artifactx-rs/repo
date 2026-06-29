#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  local script_dir
  script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
  cd -- "$script_dir/.." && pwd
}

resolve_arx() {
  if [ -n "${ARX_BIN:-}" ]; then
    if [ ! -x "$ARX_BIN" ]; then
      printf 'ARX_BIN is not executable: %s\n' "$ARX_BIN" >&2
      exit 1
    fi
    printf '%s\n' "$ARX_BIN"
    return 0
  fi

  local artifactx_dir="${ARTIFACTX_DIR:-}"
  if [ -z "$artifactx_dir" ] && [ -f /Users/joe/code/artifactx/Cargo.toml ]; then
    artifactx_dir=/Users/joe/code/artifactx
  fi

  if [ -n "$artifactx_dir" ]; then
    if [ ! -f "$artifactx_dir/Cargo.toml" ]; then
      printf 'ARTIFACTX_DIR does not contain Cargo.toml: %s\n' "$artifactx_dir" >&2
      exit 1
    fi
    cargo build --quiet --manifest-path "$artifactx_dir/Cargo.toml" -p artifactx
    printf '%s\n' "$artifactx_dir/target/debug/arx"
    return 0
  fi

  if command -v arx >/dev/null 2>&1; then
    command -v arx
    return 0
  fi

  printf 'Cannot find arx. Set ARX_BIN or ARTIFACTX_DIR.\n' >&2
  exit 1
}

recipe_version() {
  local recipe_file=$1
  python3 - <<'PY' "$recipe_file"
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    data = tomllib.load(f)
print(str(data['package']['version']).removeprefix('v'))
PY
}

ensure_repo_root() {
  local root=$1
  local arx=$2
  mkdir -p "$root/repo"
  if [ ! -f "$root/repo/arx.toml" ]; then
    "$arx" init "$root/repo"
  fi
  cp "$root/arx.toml" "$root/repo/arx.toml"

  if [ -n "${ARX_SIGNING_PRIVATE_ASC:-}" ] || [ -n "${ARX_SIGNING_PUBLIC_ASC:-}" ]; then
    if [ -z "${ARX_SIGNING_PRIVATE_ASC:-}" ] || [ -z "${ARX_SIGNING_PUBLIC_ASC:-}" ]; then
      printf 'Both ARX_SIGNING_PRIVATE_ASC and ARX_SIGNING_PUBLIC_ASC must be set together.\n' >&2
      exit 1
    fi
    mkdir -p "$root/repo/keys"
    printf '%s\n' "$ARX_SIGNING_PRIVATE_ASC" > "$root/repo/keys/private.asc"
    printf '%s\n' "$ARX_SIGNING_PUBLIC_ASC" > "$root/repo/keys/public.asc"
    chmod 0600 "$root/repo/keys/private.asc"
    chmod 0644 "$root/repo/keys/public.asc"
  fi
}

export_public_tree() {
  local root=$1
  rm -rf "$root/public"
  mkdir -p "$root/public/keys"
  cp -R "$root/repo/apt" "$root/public/apt"
  cp -R "$root/repo/yum" "$root/public/yum"
  cp "$root/repo/keys/public.asc" "$root/public/keys/public.asc"
  touch "$root/public/.nojekyll"
  cat > "$root/public/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>ArtifactX Packages</title>
<h1>ArtifactX Packages</h1>
<ul>
  <li><a href="apt/dists/stable/InRelease">apt InRelease</a></li>
  <li><a href="yum/stable/x86_64/repodata/repomd.xml">yum repomd.xml</a></li>
  <li><a href="keys/public.asc">repository public key</a></li>
</ul>
HTML
}
