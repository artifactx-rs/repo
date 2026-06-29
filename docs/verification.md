# Verification

Last local verification: 2026-06-29.

The committed repo intentionally excludes generated `dist/`, `repo/`, `public/`,
and `work/` trees. Rebuild them before trusting the feed output.

## Commands

```sh
# Syntax/static checks for maintained shell scripts.
find helpers recipes -type f \( -name '*.sh' -o -path '*/scripts/*' \) -print0 \
  | sort -z | xargs -0 -n1 bash -n
find helpers recipes -type f \( -name '*.sh' -o -path '*/scripts/*' \) -print0 \
  | sort -z | xargs -0 shellcheck -x

# Fixed-version product test.
VERSION=1.146.0 helpers/build-recipe.sh victoriametrics

# CI default version resolver path.
VERSION=latest recipes/victoriametrics/fetch.sh
recipes/victoriametrics/render-manifest.sh
helpers/smoke-package-structure.sh victoriametrics 1.146.0
helpers/smoke-repo-structure.sh

# Install smoke from the generated static public tree.
helpers/smoke-install-docker.sh victoriametrics
```

## Evidence from the current VictoriaMetrics run

- Upstream latest release resolved to `1.146.0` from the official GitHub release
  API on 2026-06-29.
- Upstream archive checksum verified:
  `20da3e2a3835d1071d2a7449df5f0e60c4095e970fb7713b1ff9aebc2040937e`.
- The official archive contained `victoria-metrics-prod`; it did not include a
  systemd unit, so the recipe used the official quick-start unit fallback.
- Built package names:
  - `victoriametrics_1.146.0_amd64.deb`
  - `victoriametrics-1.146.0-1.x86_64.rpm`
- Static repository metadata existed in `public/apt/...` and
  `public/yum/stable/x86_64/repodata/repomd.xml`.
- Docker apt smoke installed `victoriametrics` from `file:/repo/apt` and ran
  `/usr/local/bin/victoria-metrics-prod --version`.
- Docker dnf smoke installed `victoriametrics` from
  `file:///repo/yum/stable/$basearch` and ran
  `/usr/local/bin/victoria-metrics-prod --version`.
- `public/` was checked to contain no `private.asc`.

Official upstream references:

- VictoriaMetrics releases: <https://github.com/VictoriaMetrics/VictoriaMetrics/releases>
- VictoriaMetrics quick start: <https://docs.victoriametrics.com/victoriametrics/quick-start/>
