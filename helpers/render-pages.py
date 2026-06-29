#!/usr/bin/env python3
"""Render the static GitHub Pages search UI from the generated package repo."""

from __future__ import annotations

import gzip
import hashlib
import json
import pathlib
import sys
from typing import Any

DEB_TO_RPM_ARCH = {
    "amd64": "x86_64",
    "arm64": "aarch64",
}


def parse_deb_packages(path: pathlib.Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    current: dict[str, str] = {}
    current_key: str | None = None
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if not line:
                if current:
                    entries.append(current)
                    current = {}
                    current_key = None
                continue
            if line.startswith(" ") and current_key:
                current[current_key] += "\n" + line[1:]
                continue
            key, sep, value = line.partition(":")
            if not sep:
                continue
            current_key = key
            current[key] = value.lstrip()
    if current:
        entries.append(current)
    return entries


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def human_size(size: int) -> str:
    value = float(size)
    for unit in ["B", "KiB", "MiB", "GiB"]:
        if value < 1024 or unit == "GiB":
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size} B"


def rel(path: pathlib.Path, root: pathlib.Path) -> str:
    return path.relative_to(root).as_posix()


def build_catalog(public_root: pathlib.Path) -> dict[str, Any]:
    packages: dict[str, dict[str, Any]] = {}
    apt_root = public_root / "apt" / "dists" / "stable" / "main"

    for packages_gz in sorted(apt_root.glob("binary-*/Packages.gz")):
        for entry in parse_deb_packages(packages_gz):
            name = entry["Package"]
            arch = entry["Architecture"]
            version = entry["Version"]
            filename = entry["Filename"]
            description = entry.get("Description", "").split("\n", 1)[0]
            package = packages.setdefault(
                name,
                {
                    "name": name,
                    "version": version,
                    "description": description,
                    "variants": [],
                },
            )
            package["version"] = version
            package["description"] = description or package["description"]
            package["variants"].append(
                {
                    "format": "deb",
                    "manager": "apt",
                    "arch": arch,
                    "path": f"apt/{filename}",
                    "size": int(entry.get("Size", "0")),
                    "sizeHuman": human_size(int(entry.get("Size", "0"))),
                    "sha256": entry.get("SHA256", ""),
                }
            )

    for package in packages.values():
        version = package["version"]
        for deb_arch, rpm_arch in DEB_TO_RPM_ARCH.items():
            rpm_path = public_root / "yum" / "stable" / rpm_arch / f"{package['name']}-{version}-1.{rpm_arch}.rpm"
            if not rpm_path.exists():
                continue
            size = rpm_path.stat().st_size
            package["variants"].append(
                {
                    "format": "rpm",
                    "manager": "dnf",
                    "arch": rpm_arch,
                    "debArchEquivalent": deb_arch,
                    "path": rel(rpm_path, public_root),
                    "size": size,
                    "sizeHuman": human_size(size),
                    "sha256": sha256_file(rpm_path),
                }
            )

    sorted_packages = sorted(packages.values(), key=lambda item: item["name"])
    for package in sorted_packages:
        package["variants"].sort(key=lambda item: (item["format"], item["arch"]))

    return {
        "schemaVersion": 1,
        "suite": "stable",
        "component": "main",
        "packageCount": len(sorted_packages),
        "artifactCount": sum(len(package["variants"]) for package in sorted_packages),
        "packages": sorted_packages,
    }


HTML = r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ArtifactX Packages</title>
  <style>
    :root { color-scheme: light dark; --bg: #0f172a; --card: #111827; --muted: #94a3b8; --text: #e5e7eb; --accent: #38bdf8; --border: #334155; }
    @media (prefers-color-scheme: light) { :root { --bg: #f8fafc; --card: #ffffff; --muted: #475569; --text: #0f172a; --accent: #0369a1; --border: #cbd5e1; } }
    * { box-sizing: border-box; }
    body { margin: 0; font: 16px/1.5 system-ui, -apple-system, Segoe UI, sans-serif; background: var(--bg); color: var(--text); }
    header { padding: 3rem 1rem 2rem; max-width: 1120px; margin: 0 auto; }
    main { max-width: 1120px; margin: 0 auto; padding: 0 1rem 3rem; }
    h1 { font-size: clamp(2rem, 5vw, 4rem); line-height: 1; margin: 0 0 1rem; }
    .lede { max-width: 760px; color: var(--muted); margin: 0; }
    .panel, .package-card { background: color-mix(in srgb, var(--card) 92%, transparent); border: 1px solid var(--border); border-radius: 18px; box-shadow: 0 20px 40px rgb(0 0 0 / 0.16); }
    .panel { padding: 1rem; margin-bottom: 1rem; display: grid; gap: 1rem; }
    label { font-weight: 700; display: block; margin-bottom: .4rem; }
    input[type="search"] { width: 100%; border: 1px solid var(--border); border-radius: 14px; padding: .85rem 1rem; font: inherit; color: var(--text); background: transparent; }
    .stats { display: flex; flex-wrap: wrap; gap: .6rem; color: var(--muted); }
    .pill { border: 1px solid var(--border); border-radius: 999px; padding: .3rem .65rem; }
    .quick-links { display: flex; flex-wrap: wrap; gap: .75rem; }
    a { color: var(--accent); text-underline-offset: .2em; }
    #results { display: grid; gap: 1rem; }
    .package-card { padding: 1rem; }
    .package-card h2 { margin: 0 0 .35rem; font-size: 1.25rem; }
    .description { color: var(--muted); margin: 0 0 1rem; }
    .install { display: grid; gap: .5rem; margin: 1rem 0; }
    code { display: inline-block; max-width: 100%; overflow-wrap: anywhere; border: 1px solid var(--border); border-radius: 10px; padding: .35rem .5rem; background: rgb(148 163 184 / 0.12); }
    .variants { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: .5rem; padding: 0; margin: 0; list-style: none; }
    .variant { border: 1px solid var(--border); border-radius: 12px; padding: .65rem; }
    .variant strong { display: block; }
    .sha { color: var(--muted); font-size: .82rem; overflow-wrap: anywhere; }
    .empty { padding: 2rem; text-align: center; color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <h1>ArtifactX Packages</h1>
    <p class="lede">Search the generated static apt/yum package feed. This page is rebuilt from repository metadata after each scheduled package refresh.</p>
  </header>
  <main>
    <section class="panel" aria-labelledby="search-heading">
      <div>
        <h2 id="search-heading">Package search</h2>
        <label for="package-search">Search by package, description, architecture, or format</label>
        <input id="package-search" name="q" type="search" autocomplete="off" placeholder="Try vmagent, cluster, arm64, rpm" autofocus>
      </div>
      <div class="stats" aria-live="polite">
        <span class="pill" id="summary-packages">Loading packages…</span>
        <span class="pill" id="summary-artifacts">Loading artifacts…</span>
        <span class="pill">suite: stable</span>
        <span class="pill">arches: amd64, arm64</span>
      </div>
      <nav class="quick-links" aria-label="Repository links">
        <a href="apt/dists/stable/InRelease">apt InRelease</a>
        <a href="yum/stable/x86_64/repodata/repomd.xml">yum x86_64 repomd.xml</a>
        <a href="yum/stable/aarch64/repodata/repomd.xml">yum aarch64 repomd.xml</a>
        <a href="keys/public.asc">repository public key</a>
        <a href="packages.json">package catalog JSON</a>
      </nav>
    </section>
    <section id="results" aria-label="Package results"></section>
  </main>
  <script>
    const results = document.querySelector('#results');
    const search = document.querySelector('#package-search');
    const packageSummary = document.querySelector('#summary-packages');
    const artifactSummary = document.querySelector('#summary-artifacts');
    let catalog = { packages: [], packageCount: 0, artifactCount: 0 };

    function escapeHtml(value) {
      return String(value).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
    }

    function matches(pkg, query) {
      if (!query) return true;
      const haystack = [pkg.name, pkg.version, pkg.description, ...pkg.variants.flatMap(v => [v.format, v.manager, v.arch, v.path])].join(' ').toLowerCase();
      return haystack.includes(query.toLowerCase());
    }

    function render() {
      const query = search.value.trim();
      const filtered = catalog.packages.filter(pkg => matches(pkg, query));
      packageSummary.textContent = `${filtered.length} of ${catalog.packageCount} packages`;
      artifactSummary.textContent = `${catalog.artifactCount} package files`;
      if (!filtered.length) {
        results.innerHTML = '<div class="package-card empty" role="status">No packages match this search.</div>';
        return;
      }
      results.innerHTML = filtered.map(pkg => {
        const variants = pkg.variants.map(v => `
          <li class="variant">
            <strong>${escapeHtml(v.manager)} ${escapeHtml(v.arch)} · ${escapeHtml(v.format)}</strong>
            <a href="${escapeHtml(v.path)}">${escapeHtml(v.path.split('/').pop())}</a>
            <div>${escapeHtml(v.sizeHuman)}</div>
            <div class="sha">sha256: ${escapeHtml(v.sha256 || 'n/a')}</div>
          </li>`).join('');
        return `
          <article class="package-card">
            <h2>${escapeHtml(pkg.name)}</h2>
            <p class="description">${escapeHtml(pkg.description)} · version ${escapeHtml(pkg.version)}</p>
            <div class="install" aria-label="Install commands for ${escapeHtml(pkg.name)}">
              <code>sudo apt-get install ${escapeHtml(pkg.name)}</code>
              <code>sudo dnf install ${escapeHtml(pkg.name)}</code>
            </div>
            <ul class="variants">${variants}</ul>
          </article>`;
      }).join('');
    }

    fetch('packages.json')
      .then(response => {
        if (!response.ok) throw new Error(`catalog request failed: ${response.status}`);
        return response.json();
      })
      .then(data => { catalog = data; render(); })
      .catch(error => {
        results.innerHTML = `<div class="package-card empty" role="alert">${escapeHtml(error.message)}</div>`;
      });

    search.addEventListener('input', render);
  </script>
</body>
</html>
'''


def main() -> int:
    public_root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "public").resolve()
    if not public_root.exists():
        raise SystemExit(f"public root does not exist: {public_root}")
    catalog = build_catalog(public_root)
    (public_root / "packages.json").write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (public_root / "index.html").write_text(HTML, encoding="utf-8")
    print(f"Rendered Pages search UI for {catalog['packageCount']} packages and {catalog['artifactCount']} artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
