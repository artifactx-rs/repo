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
CANONICAL_REPO_BASE = "https://artifactx-rs.github.io/repo/"


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


INSTALL_SH_TEMPLATE = r'''#!/bin/sh
set -eu

REPO_BASE="${1:-${REPO_BASE:-__CANONICAL_REPO_BASE__}}"
REPO_BASE="${REPO_BASE%/}"

die() {
  printf 'artifactx repository setup: %s\n' "$*" >&2
  exit 1
}

fetch() {
  url=$1
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
    return
  fi
  die "curl or wget is required"
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "run as root, for example: curl -fsSL ${REPO_BASE}/install.sh | sudo bash -s -- ${REPO_BASE}"
  fi
}

setup_apt() {
  keyring=/usr/share/keyrings/artifactx-packages.asc
  source_list=/etc/apt/sources.list.d/artifactx-packages.list
  mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
  fetch "${REPO_BASE}/keys/public.asc" >"$keyring"
  chmod 0644 "$keyring"
  printf '%s\n' "deb [signed-by=${keyring}] ${REPO_BASE}/apt stable main" >"$source_list"
  apt-get update
  printf 'ArtifactX apt repository configured.\n'
}

setup_rpm() {
  pm=$1
  repo_file=/etc/yum.repos.d/artifactx-packages.repo
  mkdir -p /etc/yum.repos.d
  cat >"$repo_file" <<EOF
[artifactx-packages]
name=ArtifactX Packages
baseurl=${REPO_BASE}/yum/stable/\$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=${REPO_BASE}/keys/public.asc
EOF
  "$pm" -y makecache
  printf 'ArtifactX yum/dnf repository configured.\n'
}

need_root

if command -v apt-get >/dev/null 2>&1; then
  setup_apt
elif command -v dnf >/dev/null 2>&1; then
  setup_rpm dnf
elif command -v yum >/dev/null 2>&1; then
  setup_rpm yum
else
  die "no supported package manager found; expected apt-get, dnf, or yum"
fi
'''
INSTALL_SH = INSTALL_SH_TEMPLATE.replace("__CANONICAL_REPO_BASE__", CANONICAL_REPO_BASE)


HTML = r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ArtifactX Packages</title>
  <link rel="icon" href="data:,">
  <style>
    :root {
      color-scheme: light dark;
      --bg: #020617;
      --surface: #0f172a;
      --card: #111827;
      --card-strong: #172033;
      --muted: #94a3b8;
      --text: #e5e7eb;
      --heading: #f8fafc;
      --accent: #38bdf8;
      --accent-strong: #0ea5e9;
      --success: #34d399;
      --border: #334155;
      --border-soft: rgb(148 163 184 / 0.22);
      --shadow: 0 24px 70px rgb(2 6 23 / 0.42);
      --code-bg: rgb(2 6 23 / 0.55);
    }
    @media (prefers-color-scheme: light) {
      :root {
        --bg: #f8fafc;
        --surface: #eef6ff;
        --card: #ffffff;
        --card-strong: #f8fbff;
        --muted: #475569;
        --text: #0f172a;
        --heading: #020617;
        --accent: #0369a1;
        --accent-strong: #0284c7;
        --success: #047857;
        --border: #cbd5e1;
        --border-soft: rgb(15 23 42 / 0.12);
        --shadow: 0 24px 55px rgb(15 23 42 / 0.12);
        --code-bg: rgb(241 245 249 / 0.92);
      }
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      min-height: 100vh;
      font: 16px/1.55 system-ui, -apple-system, Segoe UI, sans-serif;
      background:
        radial-gradient(circle at top left, rgb(56 189 248 / 0.18), transparent 34rem),
        linear-gradient(180deg, var(--surface) 0, var(--bg) 32rem);
      color: var(--text);
    }
    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image: linear-gradient(rgb(148 163 184 / 0.06) 1px, transparent 1px), linear-gradient(90deg, rgb(148 163 184 / 0.06) 1px, transparent 1px);
      background-size: 44px 44px;
      mask-image: linear-gradient(180deg, black, transparent 40rem);
    }
    a { color: var(--accent); text-underline-offset: .22em; }
    a:hover { color: var(--accent-strong); }
    .hero, main { width: min(1180px, calc(100% - 2rem)); margin: 0 auto; }
    .hero { padding: 4rem 0 2rem; }
    .hero-grid { display: grid; grid-template-columns: minmax(0, 1.03fr) minmax(360px, .97fr); gap: 2rem; align-items: start; }
    .eyebrow, .section-kicker { color: var(--accent); font-size: .78rem; font-weight: 800; letter-spacing: .12em; text-transform: uppercase; }
    h1, h2, h3 { color: var(--heading); line-height: 1.12; }
    h1 { font-size: clamp(2.55rem, 6vw, 5.2rem); letter-spacing: -.06em; margin: .65rem 0 1rem; max-width: 10ch; }
    h2 { font-size: clamp(1.35rem, 2.5vw, 1.9rem); letter-spacing: -.025em; margin: 0; }
    h3 { font-size: 1rem; margin: 0; }
    .lede { max-width: 720px; color: var(--muted); font-size: 1.08rem; margin: 0; }
    .hero-actions { display: flex; flex-wrap: wrap; gap: .75rem; margin-top: 1.5rem; }
    .button, button {
      appearance: none;
      border: 1px solid transparent;
      border-radius: 999px;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: .45rem;
      font: inherit;
      font-weight: 800;
      min-height: 2.55rem;
      padding: .6rem 1rem;
      text-decoration: none;
      transition: transform .15s ease, border-color .15s ease, background .15s ease;
    }
    .button:hover, button:hover { transform: translateY(-1px); }
    .button.primary, .copy-button { background: var(--accent); color: #00111f; box-shadow: 0 12px 28px rgb(14 165 233 / 0.25); }
    .button.secondary { background: rgb(148 163 184 / 0.12); border-color: var(--border-soft); color: var(--text); }
    .panel, .package-list, .package-row, .setup-panel, .command-card {
      background: color-mix(in srgb, var(--card) 94%, transparent);
      border: 1px solid var(--border-soft);
      box-shadow: var(--shadow);
    }
    .setup-panel { border-radius: 28px; padding: 1.25rem; }
    .setup-panel > p { color: var(--muted); margin: .55rem 0 1rem; }
    .setup-header { display: flex; justify-content: space-between; gap: 1rem; align-items: start; margin-bottom: .9rem; }
    .setup-badge { border: 1px solid var(--border-soft); border-radius: 999px; color: var(--muted); font-size: .82rem; font-weight: 750; padding: .25rem .65rem; white-space: nowrap; }
    .setup-grid { display: grid; gap: .85rem; }
    .command-card { border-radius: 20px; padding: 1rem; background: color-mix(in srgb, var(--card-strong) 95%, transparent); box-shadow: none; }
    .command-card header { display: flex; justify-content: space-between; align-items: start; gap: 1rem; margin-bottom: .75rem; }
    .manager { color: var(--muted); font-size: .86rem; margin-top: .15rem; }
    pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    pre {
      margin: 0 0 .75rem;
      overflow: auto;
      border: 1px solid var(--border-soft);
      border-radius: 16px;
      background: var(--code-bg);
      max-height: 9.5rem;
    }
    pre code { display: block; padding: .85rem; white-space: pre-wrap; overflow-wrap: anywhere; }
    code.inline-code, .install code {
      display: inline-block;
      max-width: 100%;
      overflow-wrap: anywhere;
      border: 1px solid var(--border-soft);
      border-radius: 12px;
      padding: .4rem .55rem;
      background: rgb(148 163 184 / 0.12);
    }
    .copy-button { width: 100%; }
    .copy-button[data-copied="true"] { background: var(--success); color: #022c22; }
    .copy-status { color: var(--success); min-height: 1.4rem; margin: .75rem 0 0; font-size: .92rem; }
    main { padding: 0 0 3rem; }
    .panel { border-radius: 24px; padding: 1.15rem; margin: 1rem 0; display: grid; gap: 1rem; position: sticky; top: .75rem; z-index: 2; backdrop-filter: blur(14px); }
    .search-head { display: grid; grid-template-columns: minmax(0, 1fr) minmax(260px, .72fr); gap: 1rem; align-items: end; }
    label { color: var(--muted); display: block; font-size: .92rem; font-weight: 700; margin: .35rem 0 .45rem; }
    input[type="search"] { width: 100%; border: 1px solid var(--border); border-radius: 16px; padding: .9rem 1rem; font: inherit; color: var(--text); background: rgb(148 163 184 / 0.08); outline: none; }
    input[type="search"]:focus { border-color: var(--accent); box-shadow: 0 0 0 4px rgb(56 189 248 / 0.18); }
    .stats, .quick-links, .package-meta { display: flex; flex-wrap: wrap; gap: .55rem; }
    .stats { justify-content: flex-end; color: var(--muted); }
    .pill { border: 1px solid var(--border-soft); border-radius: 999px; padding: .35rem .68rem; background: rgb(148 163 184 / 0.08); }
    .quick-links { border-top: 1px solid var(--border-soft); padding-top: .85rem; }
    .quick-links a { font-weight: 700; }
    #results { display: grid; gap: .85rem; }
    .package-list { border-radius: 24px; overflow: hidden; }
    .package-list-head, .package-row { display: grid; grid-template-columns: minmax(0, 1fr); gap: .4rem; align-items: start; padding: .72rem 1rem; }
    .package-list-head { background: rgb(148 163 184 / 0.10); border-bottom: 1px solid var(--border-soft); color: var(--muted); font-size: .76rem; font-weight: 850; letter-spacing: .09em; text-transform: uppercase; }
    .package-row { border: 0; border-bottom: 1px solid var(--border-soft); box-shadow: none; }
    .package-row:last-child { border-bottom: 0; }
    .package-row h3 { font-size: 1rem; letter-spacing: -.015em; margin: 0; overflow-wrap: anywhere; }
    .empty { border-radius: 22px; padding: 2.25rem; text-align: center; color: var(--muted); }
    @media (max-width: 900px) {
      .hero { padding-top: 2.5rem; }
      .hero-grid, .search-head { grid-template-columns: 1fr; }
      h1 { max-width: 12ch; }
      .stats { justify-content: flex-start; }
      .panel { position: static; }
      .package-list-head { display: none; }
      .package-row { padding: 1rem; }
    }
    @media (max-width: 520px) {
      .hero, main { width: min(100% - 1rem, 1180px); }
      .hero-actions, .setup-header, .command-card header { display: grid; }
      .setup-panel, .panel, .package-list { border-radius: 20px; }
      .setup-panel, .panel { padding: .9rem; }
      .button, button { width: 100%; }
      h1 { font-size: clamp(2.2rem, 13vw, 3.1rem); }
      .command-card pre { display: none; }
    }
  </style>
</head>
<body>
  <header class="hero">
    <div class="hero-grid">
      <div class="hero-copy">
        <div class="eyebrow">Static apt/yum feed · amd64 + arm64</div>
        <h1>ArtifactX Packages</h1>
        <p class="lede">Search the generated package feed, copy a repository setup command, then install VictoriaMetrics components with apt or dnf.</p>
        <div class="hero-actions" aria-label="Primary actions">
          <a class="button primary" href="#repo-setup">Add repository</a>
          <a class="button secondary" href="#package-search">Search packages</a>
        </div>
      </div>
      <section class="setup-panel" id="repo-setup" aria-labelledby="repo-setup-heading">
        <div class="setup-header">
          <div>
            <div class="section-kicker">Repository setup</div>
            <h2 id="repo-setup-heading">One-click repository setup</h2>
          </div>
          <span class="setup-badge">apt · dnf · yum</span>
        </div>
        <p>Run one command to add this feed. The script detects apt, dnf, or yum and configures the matching repository with the public metadata signing key.</p>
        <div class="setup-grid">
          <article class="command-card">
            <header>
              <div>
                <h3>Auto-detect Linux package manager</h3>
                <div class="manager">adds the repository only; install package names from the list below</div>
              </div>
              <span class="setup-badge">amd64 · arm64</span>
            </header>
            <pre><code id="setup-command">Preparing setup command…</code></pre>
            <button type="button" class="copy-button" data-copy-target="setup-command" data-copy-label="repository">Copy one-click setup command</button>
          </article>
        </div>
        <p id="copy-status" class="copy-status" role="status" aria-live="polite"></p>
      </section>
    </div>
  </header>
  <main>
    <section class="panel" aria-labelledby="search-heading">
      <div class="search-head">
        <div>
          <h2 id="search-heading">Package search</h2>
          <label for="package-search">Search by package, description, architecture, or format</label>
          <input id="package-search" name="q" type="search" autocomplete="off" placeholder="Try vmagent, cluster, arm64, rpm">
        </div>
        <div class="stats" aria-live="polite">
          <span class="pill" id="summary-packages">Loading packages…</span>
          <span class="pill" id="summary-artifacts">Loading artifacts…</span>
          <span class="pill">suite: stable</span>
          <span class="pill">arches: amd64, arm64</span>
        </div>
      </div>
      <nav class="quick-links" aria-label="Repository links">
        <a href="apt/dists/stable/InRelease" data-repo-path="apt/dists/stable/InRelease">apt InRelease</a>
        <a href="yum/stable/x86_64/repodata/repomd.xml" data-repo-path="yum/stable/x86_64/repodata/repomd.xml">yum x86_64 repomd.xml</a>
        <a href="yum/stable/aarch64/repodata/repomd.xml" data-repo-path="yum/stable/aarch64/repodata/repomd.xml">yum aarch64 repomd.xml</a>
        <a href="keys/public.asc" data-repo-path="keys/public.asc">repository public key</a>
        <a href="install.sh" data-repo-path="install.sh">one-click setup script</a>
        <a href="packages.json" data-repo-path="packages.json">package catalog JSON</a>
      </nav>
    </section>
    <section id="results" aria-label="Package results"></section>
  </main>
  <script>
    const results = document.querySelector('#results');
    const search = document.querySelector('#package-search');
    const packageSummary = document.querySelector('#summary-packages');
    const artifactSummary = document.querySelector('#summary-artifacts');
    const copyStatus = document.querySelector('#copy-status');
    let catalog = { packages: [], packageCount: 0, artifactCount: 0 };

    function escapeHtml(value) {
      return String(value).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
    }

    function repoBaseFromLocation(href) {
      const url = new URL(href);
      let path = url.pathname;
      if (path.endsWith('/')) return `${url.origin}${path}`;
      if (path.endsWith('/index.html')) return `${url.origin}${path.slice(0, -'index.html'.length)}`;
      if (path.split('/').pop().includes('.')) return `${url.origin}${path.slice(0, path.lastIndexOf('/') + 1)}`;
      return `${url.origin}${path}/`;
    }
    window.repoBaseFromLocation = repoBaseFromLocation;
    const repoBase = repoBaseFromLocation(window.location.href);
    window.repoBase = repoBase;

    function repoUrl(path) {
      return new URL(path, repoBase).href;
    }
    window.repoUrl = repoUrl;

    function renderRepositoryCommands() {
      document.querySelector('#setup-command').textContent = `curl -fsSL ${repoBase}install.sh | sudo bash -s -- ${repoBase}`;
    }

    function renderRepositoryLinks() {
      document.querySelectorAll('[data-repo-path]').forEach(link => {
        link.href = repoUrl(link.dataset.repoPath);
      });
    }

    function fallbackCopy(text) {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      const copied = document.execCommand('copy');
      textarea.remove();
      if (!copied) throw new Error('copy command was rejected');
    }

    async function copyCommand(button) {
      const target = document.querySelector(`#${button.dataset.copyTarget}`);
      const label = button.dataset.copyLabel;
      const text = target.textContent.trim();
      try {
        try {
          if (!navigator.clipboard || !window.isSecureContext) throw new Error('clipboard API unavailable');
          await navigator.clipboard.writeText(text);
        } catch (_clipboardError) {
          fallbackCopy(text);
        }
        copyStatus.textContent = `Copied ${label} setup command.`;
        button.dataset.copied = 'true';
        const originalText = button.textContent;
        button.textContent = 'Copied';
        window.setTimeout(() => {
          button.dataset.copied = 'false';
          button.textContent = originalText;
        }, 1800);
      } catch (error) {
        copyStatus.textContent = `Copy failed: ${error.message}. Select the command manually.`;
      }
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
        results.innerHTML = '<div class="package-list empty" role="status">No packages match this search.</div>';
        return;
      }
      const rows = filtered.map(pkg => {
        return `
          <article class="package-row" role="listitem" aria-label="${escapeHtml(pkg.name)}">
            <h3>${escapeHtml(pkg.name)}</h3>
          </article>`;
      }).join('');
      results.innerHTML = `
        <div class="package-list" role="list" aria-label="Filtered packages">
          <div class="package-list-head" aria-hidden="true">
            <span>Package name</span>
          </div>
          ${rows}
        </div>`;
    }

    renderRepositoryCommands();
    renderRepositoryLinks();
    document.querySelectorAll('[data-copy-target]').forEach(button => {
      button.addEventListener('click', () => copyCommand(button));
    });

    fetch(repoUrl('packages.json'))
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
    install_script = public_root / "install.sh"
    install_script.write_text(INSTALL_SH, encoding="utf-8")
    install_script.chmod(0o755)
    print(f"Rendered Pages search UI for {catalog['packageCount']} packages and {catalog['artifactCount']} artifacts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
