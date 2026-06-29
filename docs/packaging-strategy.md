# Packaging strategy

This feed follows the official VictoriaMetrics Docker image boundaries, not the
upstream release-archive boundaries.

Why: the official Docker Hub namespace publishes separate images for the runtime
components (`victoria-metrics`, `vmagent`, `vmalert`, `vmauth`, `vminsert`,
`vmselect`, `vmstorage`, `vmbackup`, `vmrestore`, `vmctl`, and others). The
GitHub release assets are coarser: the community `vmutils` archive is about
118 MiB compressed for amd64 and contains seven binaries, while the cluster
archive contains three binaries. Packaging those archives as one OS package would
force users to install tools they do not run and would make upgrades, service
ownership, and smoke tests too broad.

## Architecture scope

Supported package architectures are intentionally only:

| ArtifactX manifest arch | Debian arch | RPM arch | Docker platform |
| --- | --- | --- | --- |
| `amd64` | `amd64` | `x86_64` | `linux/amd64` |
| `arm64` | `arm64` | `aarch64` | `linux/arm64` |

Do not add `386`, `arm/v7`, `ppc64le`, or other cold platforms unless the support
matrix and Docker install smoke are expanded first.

## Package split rules

1. **One runtime binary/service per package.** Match the official Docker image
   component boundary even when the downloaded release archive contains multiple
   binaries.
2. **Use namespaced package names for component packages.** The single-node
   server keeps the simple package name `victoriametrics`; component packages
   should use names such as `victoriametrics-vmagent`,
   `victoriametrics-vmalert`, `victoriametrics-vmauth`,
   `victoriametrics-vminsert`, `victoriametrics-vmselect`, and
   `victoriametrics-vmstorage`.
3. **Keep CLI tools separate from daemons.** `vmctl`, `vmalert-tool`, `vmbackup`,
   and `vmrestore` should be separate packages. Do not bundle all of `vmutils`
   into one package.
4. **Only package community assets by default.** Enterprise-only binaries such as
   `vmgateway` or `vmbackupmanager` need an explicit license/support decision
   before entering this feed.
5. **Do not invent config.** Package official service/config files when upstream
   ships or documents them. If Docker examples mount a config file, keep it as an
   example or recipe fixture until an installable default is reviewed.
6. **Metapackages are allowed later but payload-free.** If users want a cluster
   convenience install, add a `victoriametrics-cluster` metapackage that depends
   on `victoriametrics-vminsert`, `victoriametrics-vmselect`, and
   `victoriametrics-vmstorage`; do not duplicate binaries.

## VictoriaMetrics phase plan

| Phase | Upstream input | Packages | Reason |
| --- | --- | --- | --- |
| 1 | `victoria-metrics-linux-{arch}-v*.tar.gz` | `victoriametrics` | Already smoke-tested as the smallest single-node server package. |
| 2 | `vmutils-linux-{arch}-v*.tar.gz` | `victoriametrics-vmagent`, `victoriametrics-vmalert`, `victoriametrics-vmauth`, `victoriametrics-vmctl`, `victoriametrics-vmbackup`, `victoriametrics-vmrestore`, `victoriametrics-vmalert-tool` | Mirrors official per-component Docker images and avoids a 100+ MiB all-tools package. |
| 3 | `victoria-metrics-linux-{arch}-v*-cluster.tar.gz` | `victoriametrics-vminsert`, `victoriametrics-vmselect`, `victoriametrics-vmstorage` | Mirrors official cluster images and lets operators install only the roles they run. |
| Later | VictoriaLogs / VictoriaTraces assets | Separate recipes | Different product families; do not mix with metrics packages. |

## Current upstream evidence for v1.146.0

- Single-node archives: amd64 ~12.64 MiB, arm64 ~12.09 MiB.
- Cluster archives: amd64 ~27.40 MiB containing `vminsert-prod`,
  `vmselect-prod`, `vmstorage-prod`; arm64 ~26.75 MiB.
- Community vmutils archives: amd64 ~117.72 MiB containing `vmagent-prod`,
  `vmalert-prod`, `vmalert-tool-prod`, `vmauth-prod`, `vmbackup-prod`,
  `vmrestore-prod`, `vmctl-prod`; arm64 ~110.00 MiB.

Sources:

- Official Docker Hub namespace: <https://hub.docker.com/u/victoriametrics>
- Official release assets: <https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v1.146.0>
- Component list: <https://docs.victoriametrics.com/victoriametrics/single-server-victoriametrics/#components>
- Cluster service split: <https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/#architecture-overview>
