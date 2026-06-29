# ArtifactX Packages

Experimental static package feed built with ArtifactX itself.

This repo is the dogfood surface for `arx pack` + `arx add` + `arx publish`:
recipes fetch official upstream release assets, render ArtifactX pack manifests,
build `.deb` and `.rpm` packages, then publish a static apt/yum repository under
`public/`.

The first recipe is VictoriaMetrics community edition, split by official Docker
component boundary.

## Repository contract

```text
artifactx-packages/
  arx.toml                  # desired ArtifactX repo config copied into generated repo/
  .github/workflows/        # scheduled/manual CI refresh
  helpers/                  # reusable fetch/build/smoke/publish helpers
  policy/                   # signing and support matrix
  recipes/
    victoriametrics/
      recipe.toml           # owner, source, outputs, matrix, refresh policy
      components.tsv        # package -> binary -> upstream archive mapping
      arx-pack.toml.in      # ArtifactX package manifest template
      fetch.sh              # official upstream download + checksum verification
      render-manifest.sh    # renders one work/.../manifest per component package
      systemd/              # official service fallback only
      scripts/              # packaging glue derived from official install prerequisites
      smoke/                # recipe-level checks
  dist/                     # generated packages; ignored
  repo/                     # generated ArtifactX repo root with private key; ignored
  public/                   # static publish tree safe for HTTP/GitHub Pages; ignored
  work/                     # fetched/staged upstream inputs; ignored
```

Generated directories are never hand-edited. `public/` is the only tree intended
for static hosting; `repo/` contains signing private key material and must stay
private.

## Build VictoriaMetrics locally

From this repo:

```sh
helpers/build-recipe.sh victoriametrics
```

The helper resolves ArtifactX in this order:

1. `ARX_BIN=/path/to/arx`
2. `ARX_DOCKER_IMAGE=ghcr.io/artifactx-rs/arx:latest` (runs the container directly with this repo mounted)
3. `ARTIFACTX_DIR=/path/to/artifactx` (builds `target/debug/arx`)
4. `/Users/joe/code/artifactx` when present
5. `arx` on `PATH`

By default the helper builds both supported architectures (`amd64 arm64`). Use an explicit upstream version or the current GitHub release:

```sh
VERSION=1.146.0 helpers/build-recipe.sh victoriametrics
VERSION=latest helpers/build-recipe.sh victoriametrics
ARCH=amd64 VERSION=1.146.0 helpers/build-recipe.sh victoriametrics
ARCHES="amd64 arm64" VERSION=latest helpers/build-recipe.sh victoriametrics
ARX_DOCKER_IMAGE=ghcr.io/artifactx-rs/arx:latest VERSION=1.146.0 helpers/build-recipe.sh victoriametrics
```

When using `ARX_DOCKER_IMAGE` on an Apple Silicon or mixed-platform local Docker
host, set `ARX_DOCKER_PLATFORM=linux/arm64` or `linux/amd64` only if Docker does
not select the expected image variant automatically.

Expected output for version `1.146.0`: 44 package files under
`dist/victoriametrics/` (`11 packages × 2 arches × deb/rpm`). The logical package
names are:

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

Expected static repository paths:

- `public/index.html` — GitHub Pages package search UI
- `public/install.sh` — one-command client repository setup script
- `public/packages.json` — generated search catalog from the published repo metadata
- `public/apt/dists/stable/InRelease`
- `public/apt/dists/stable/main/binary-amd64/Packages.gz`
- `public/apt/dists/stable/main/binary-arm64/Packages.gz`
- `public/yum/stable/x86_64/repodata/repomd.xml`
- `public/yum/stable/aarch64/repodata/repomd.xml`
- `public/keys/public.asc`

## Client setup

The generated Pages UI includes the same one-click setup command. It adds the
repository only; then use your package manager to install any package name shown
on the page.

```sh
curl -fsSL https://artifactx-rs.github.io/repo/install.sh | sudo bash
```

Package payload signing is intentionally out of scope for this feed; repository
metadata is signed by ArtifactX.

## Package split policy

VictoriaMetrics has many components. This feed follows the official Docker image
boundaries instead of publishing giant tarball-shaped packages: one runtime
binary/service per deb/rpm package, only `amd64` and `arm64`, no cold Docker
platforms. See `docs/packaging-strategy.md`.

## Official-source boundary

VictoriaMetrics inputs come from official sources only:

- release assets and checksums from `VictoriaMetrics/VictoriaMetrics` GitHub releases;
- component binaries from those release archives;
- `victoriametrics.service` from the single-node release archive when present,
  otherwise the official quick-start service unit kept as a fallback copy;
- no local config file is invented because upstream's documented install uses
  service flags rather than a standalone config file.

Maintainer scripts are attached only to the `victoriametrics` service package:
they create the official runtime user/group/data directory and reload systemd
when present. Component tool packages install only their binary payloads.


## Pages search E2E

The generated Pages UI is intentionally static: `helpers/render-pages.py` reads
the published apt/yum tree, writes `public/packages.json`, and renders
`public/index.html`. Run the browser test locally after a package build:

```sh
npm ci
npm run e2e:install
npm run e2e
```

## CI refresh

`.github/workflows/refresh.yml` runs on a schedule and manually. It builds
ArtifactX from source, runs the recipe, checks private-key leakage, smoke-installs
packages, runs Playwright E2E against the generated Pages search UI, uploads
generated packages/static repo as artifacts, and can deploy `public/` to GitHub
Pages when Pages is enabled.

For a client-stable public repo, configure stable signing key secrets:

- `ARX_SIGNING_PRIVATE_ASC`
- `ARX_SIGNING_PUBLIC_ASC`

Without those secrets CI uses an ephemeral generated key, which is fine for
product tests but not for long-lived clients.

## Add another package

1. Copy `recipes/victoriametrics/` to a new recipe directory.
2. Update `recipe.toml`, `components.tsv`, `fetch.sh`, and `arx-pack.toml.in`.
3. Keep package-specific service/config files inside that recipe.
4. Reuse `helpers/build-recipe.sh <recipe>` and add recipe-specific smoke checks.
5. Do not commit `dist/`, `repo/`, `public/`, `work/`, or private keys.
