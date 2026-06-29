# ArtifactX Packages

Experimental static package feed built with ArtifactX itself.

This repo is the dogfood surface for `arx pack` + `arx add` + `arx publish`:
recipes fetch official upstream release assets, render ArtifactX pack manifests,
build `.deb` and `.rpm` packages, then publish a static apt/yum repository under
`public/`.

The first recipe is VictoriaMetrics single-node community edition.

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
      arx-pack.toml.in      # ArtifactX package manifest template
      fetch.sh              # official upstream download + checksum verification
      render-manifest.sh    # renders work/.../arx-pack.toml
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
2. `ARTIFACTX_DIR=/path/to/artifactx` (builds `target/debug/arx`)
3. `/Users/joe/code/artifactx` when present
4. `arx` on `PATH`

Use an explicit upstream version or the current GitHub release:

```sh
VERSION=1.146.0 helpers/build-recipe.sh victoriametrics
VERSION=latest helpers/build-recipe.sh victoriametrics
```

Expected package names for version `1.146.0`:

- `dist/victoriametrics/victoriametrics_1.146.0_amd64.deb`
- `dist/victoriametrics/victoriametrics-1.146.0-1.x86_64.rpm`

Expected static repository paths:

- `public/apt/dists/stable/InRelease`
- `public/apt/dists/stable/main/binary-amd64/Packages.gz`
- `public/yum/stable/x86_64/repodata/repomd.xml`
- `public/keys/public.asc`

## Client snippets

Replace the base URL with the static host that serves `public/`.

### apt

```sh
curl -fsSL https://packages.example.invalid/keys/public.asc \
  | sudo tee /usr/share/keyrings/artifactx-packages.asc >/dev/null
printf '%s\n' \
  'deb [signed-by=/usr/share/keyrings/artifactx-packages.asc] https://packages.example.invalid/apt stable main' \
  | sudo tee /etc/apt/sources.list.d/artifactx-packages.list
sudo apt-get update
sudo apt-get install victoriametrics
```

### dnf/yum

```ini
[artifactx-packages]
name=ArtifactX Packages
baseurl=https://packages.example.invalid/yum/stable/$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.example.invalid/keys/public.asc
```

Then:

```sh
sudo dnf install victoriametrics
```

Package payload signing is intentionally out of scope for phase one; repository
metadata is signed by ArtifactX.

## Official-source boundary

VictoriaMetrics inputs come from official sources only:

- release asset and checksum from `VictoriaMetrics/VictoriaMetrics` GitHub releases;
- `victoria-metrics-prod` binary from that release archive;
- `victoriametrics.service` from the release archive when present, otherwise the
  official quick-start service unit kept as an exact fallback copy;
- no local config file is invented for the single-node package because upstream's
  documented install uses service flags rather than a standalone config file.

Maintainer scripts only create the official runtime user/group/data directory and
reload systemd when present. They do not alter the upstream service flags.

## CI refresh

`.github/workflows/refresh.yml` runs on a schedule and manually. It builds
ArtifactX from source, runs the recipe, uploads generated packages/static repo as
artifacts, and can deploy `public/` to GitHub Pages when Pages is enabled.

For a client-stable public repo, configure stable signing key secrets:

- `ARX_SIGNING_PRIVATE_ASC`
- `ARX_SIGNING_PUBLIC_ASC`

Without those secrets CI uses an ephemeral generated key, which is fine for
product tests but not for long-lived clients.

## Add another package

1. Copy `recipes/victoriametrics/` to a new recipe directory.
2. Update `recipe.toml`, `fetch.sh`, and `arx-pack.toml.in`.
3. Keep package-specific service/config files inside that recipe.
4. Reuse `helpers/build-recipe.sh <recipe>` and add recipe-specific smoke checks.
5. Do not commit `dist/`, `repo/`, `public/`, `work/`, or private keys.
