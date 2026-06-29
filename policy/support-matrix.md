# Support matrix

Phase one is intentionally narrow.

| Recipe | Upstream variant | Package name | Arch | deb | rpm | Install smoke |
| --- | --- | --- | --- | --- | --- | --- |
| `victoriametrics` | community single-node | `victoriametrics` | `amd64` / `x86_64` | Debian/Ubuntu family | RHEL/Fedora family | Docker apt + dnf smoke helper |

Rules:

- Add an architecture only after CI can run install smoke for it.
- Add a distro family only when package-manager install succeeds from `public/`.
- Keep one yum repo (`stable`) and one apt suite/component (`stable main`) until
  a concrete lifecycle need appears.
- Recipe names and package names must be lowercase and conform to both Debian and
  RPM naming expectations.
