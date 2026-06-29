# VictoriaMetrics recipe

Packages VictoriaMetrics community single-node release assets into Debian and
RPM packages named `victoriametrics` for `amd64` and `arm64` only.

Official upstream inputs:

- GitHub release archive: `victoria-metrics-linux-amd64-v<VERSION>.tar.gz`
- GitHub checksum file: `victoria-metrics-linux-amd64-v<VERSION>_checksums.txt`
- Binary payload: `victoria-metrics-prod`
- Systemd unit: release archive `victoriametrics.service` when present;
  otherwise the official quick-start service unit in `systemd/`.

No config file is packaged for phase one because the official single-node
quick-start documents command-line flags in the systemd service, not a separate
first-party config file. If upstream adds a config file, add it under this recipe
and list the installed path in `config_files`.

Future VictoriaMetrics components must be separate packages following `docs/packaging-strategy.md`; do not bundle the `vmutils` or cluster archives into one package.
