# VictoriaMetrics recipe

Packages VictoriaMetrics community release assets into split Debian and RPM
packages for `amd64` and `arm64` only. The split follows the official Docker
component boundary instead of the coarse upstream tarball boundary.

## Outputs

This recipe currently emits 11 logical packages; for two architectures and two
package formats that is 44 generated files:

- `victoriametrics` → `/usr/local/bin/victoria-metrics-prod` + `victoriametrics.service`
- `victoriametrics-vmagent` → `/usr/local/bin/vmagent-prod`
- `victoriametrics-vmalert` → `/usr/local/bin/vmalert-prod`
- `victoriametrics-vmauth` → `/usr/local/bin/vmauth-prod`
- `victoriametrics-vmctl` → `/usr/local/bin/vmctl-prod`
- `victoriametrics-vmbackup` → `/usr/local/bin/vmbackup-prod`
- `victoriametrics-vmrestore` → `/usr/local/bin/vmrestore-prod`
- `victoriametrics-vmalert-tool` → `/usr/local/bin/vmalert-tool-prod`
- `victoriametrics-vminsert` → `/usr/local/bin/vminsert-prod`
- `victoriametrics-vmselect` → `/usr/local/bin/vmselect-prod`
- `victoriametrics-vmstorage` → `/usr/local/bin/vmstorage-prod`

## Official upstream inputs

- Single-node archive: `victoria-metrics-linux-{arch}-v<VERSION>.tar.gz`
- Vmutils archive: `vmutils-linux-{arch}-v<VERSION>.tar.gz`
- Cluster archive: `victoria-metrics-linux-{arch}-v<VERSION>-cluster.tar.gz`
- Matching upstream checksum file for each archive.
- Systemd unit for `victoriametrics`: release archive `victoriametrics.service`
  when present; otherwise the official quick-start service unit in `systemd/`.

No config file is packaged because the official single-node quick-start
documents command-line flags in the systemd service, not a separate first-party
config file. If upstream adds a config file, add it under this recipe and list
the installed path in the package manifest.

Component definitions live in `components.tsv`. Do not collapse `vmutils` or the
cluster archive into giant packages; see `docs/packaging-strategy.md`.
