# Support matrix

The feed is intentionally narrow: VictoriaMetrics community assets only,
official component boundaries only, and only the two hot Linux architectures.

| Recipe | Upstream variant | Package names | Arch | deb | rpm | Install smoke |
| --- | --- | --- | --- | --- | --- | --- |
| `victoriametrics` | community components | 11 packages from `recipes/victoriametrics/components.tsv` | `amd64` / `arm64` | Debian/Ubuntu family | RHEL/Fedora family | Docker apt + dnf smoke helper for `linux/amd64` and `linux/arm64` |

Rules:

- Supported architectures are only `amd64` and `arm64` for Debian, mapped to
  `x86_64` and `aarch64` for RPM. Ignore Docker's colder `386`, `arm/v7`, and
  `ppc64le` platforms until there is a user need and install smoke coverage.
- Add a distro family only when package-manager install succeeds from `public/`.
- Keep one yum repo (`stable`) and one apt suite/component (`stable main`) until
  a concrete lifecycle need appears.
- Follow official Docker image/component boundaries for package splits; do not
  publish a giant `vmutils` package or giant cluster package.
- Recipe names and package names must be lowercase and conform to both Debian and
  RPM naming expectations.
