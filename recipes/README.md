# Recipes

Each recipe owns one upstream package family and must keep all upstream-specific
payload policy together:

- `recipe.toml` declares owner, upstream source, output names, arches, distro
  families, dependencies, official config paths, smoke tests, refresh policy, and
  rollback signal.
- `fetch.sh` downloads official inputs and verifies upstream checksums.
- `render-manifest.sh` renders `work/<recipe>/<version>/arx-pack.toml`.
- `arx-pack.toml.in` is the ArtifactX package manifest template.
- `systemd/`, `config/`, and `scripts/` are recipe-scoped.
- `smoke/` contains checks that make the package safe to publish.

Do not share giant per-package conditionals in `helpers/`; add a new recipe
folder instead.
