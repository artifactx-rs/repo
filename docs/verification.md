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

actionlint .github/workflows/refresh.yml

# Generated artifact secret-leak guard after a build.
helpers/smoke-no-private-key-leak.sh

# Fixed-version product test for all supported architectures.
VERSION=1.146.0 helpers/build-recipe.sh victoriametrics

# Inspect generated artifact cardinality.
find dist/victoriametrics -type f | wc -l
helpers/smoke-repo-structure.sh

# CI default version resolver path for one architecture.
ARCH=amd64 VERSION=latest recipes/victoriametrics/fetch.sh
recipes/victoriametrics/render-manifest.sh
helpers/smoke-package-structure.sh victoriametrics 1.146.0 amd64 victoriametrics
helpers/smoke-repo-structure.sh

# Install smoke from the generated static public tree.
helpers/smoke-install-docker.sh victoriametrics
```

## Evidence from the current VictoriaMetrics run

- Upstream latest release resolved to `1.146.0` from the official GitHub releases/latest
  redirect on 2026-06-29.
- Upstream single-node, vmutils, and cluster archives plus checksum files verified
  for both `amd64` and `arm64`.
- The recipe staged 11 logical packages from `components.tsv` and built 44 files
  (`11 packages × 2 arches × deb/rpm`) under `dist/victoriametrics/`.
- Built logical package names:
  - `victoriametrics`
  - `victoriametrics-vmagent`
  - `victoriametrics-vmalert`
  - `victoriametrics-vmauth`
  - `victoriametrics-vmctl`
  - `victoriametrics-vmbackup`
  - `victoriametrics-vmrestore`
  - `victoriametrics-vmalert-tool`
  - `victoriametrics-vminsert`
  - `victoriametrics-vmselect`
  - `victoriametrics-vmstorage`
- Package structure smoke passed for every logical package on both `amd64`
  and `arm64`.
- Static repository metadata existed in `public/apt/...` and both
  `public/yum/stable/x86_64/repodata/repomd.xml` and
  `public/yum/stable/aarch64/repodata/repomd.xml`.
- Generated repo indexes contained 22 apt package entries and 22 yum package
  entries, matching 11 packages across two architectures.
- Docker apt/dnf smoke passed on `linux/amd64` and `linux/arm64`: each run
  installed all 11 component packages from `public/` and checked every installed
  binary with a version/help probe.
- `helpers/smoke-no-private-key-leak.sh` checked `public/`, `dist/`, and `work/`
  for `private.asc`, PGP private-key markers, and private-key paths in package
  payload listings.

Official upstream references:

- VictoriaMetrics releases: <https://github.com/VictoriaMetrics/VictoriaMetrics/releases>
- VictoriaMetrics Docker Hub namespace: <https://hub.docker.com/u/victoriametrics>
- VictoriaMetrics component list: <https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#components>
- VictoriaMetrics quick start: <https://docs.victoriametrics.com/victoriametrics/quick-start/>
- VictoriaMetrics cluster architecture: <https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/#architecture-overview>
