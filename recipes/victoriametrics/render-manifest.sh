#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
# shellcheck source=/dev/null
. "$root/work/victoriametrics/current.env"

template="$script_dir/arx-pack.toml.in"
postinst="$script_dir/scripts/postinst.sh"
postrm="$script_dir/scripts/postrm.sh"
test -f "$template"
test -f "$COMPONENTS_FILE"
test -x "$postinst"
test -x "$postrm"
rm -rf "$MANIFEST_DIR"
mkdir -p "$MANIFEST_DIR"
: > "$MANIFESTS_FILE"

python3 - <<'PY' "$template" "$MANIFEST_DIR" "$MANIFESTS_FILE" "$VERSION" "$ARCH" "$STAGE_DIR" "$COMPONENTS_FILE" "$postinst" "$postrm"
import csv
import pathlib
import sys

template_path, manifest_dir, manifests_file, version, arch, stage_dir, components_file, postinst, postrm = sys.argv[1:]
template = pathlib.Path(template_path).read_text()
manifest_dir = pathlib.Path(manifest_dir)
stage_dir = pathlib.Path(stage_dir)
rows = []
with open(components_file, newline='') as f:
    for row in csv.DictReader(f, delimiter='\t'):
        rows.append(row)

with open(manifests_file, 'w') as out:
    for row in rows:
        package = row['package']
        binary = row['binary']
        service = row['service'] == 'yes'
        package_stage = stage_dir / package
        binary_path = package_stage / 'usr/local/bin' / binary
        if not binary_path.exists():
            raise SystemExit(f'missing staged binary: {binary_path}')
        service_entry = ''
        scripts_table = ''
        if service:
            service_path = package_stage / 'usr/lib/systemd/system/victoriametrics.service'
            if not service_path.exists():
                raise SystemExit(f'missing staged service: {service_path}')
            service_entry = f'''
[[files]]
source = "{service_path}"
dest = "/usr/lib/systemd/system/victoriametrics.service"
mode = "0644"
'''
            scripts_table = f'''
[scripts]
postinst = "{postinst}"
postrm = "{postrm}"
'''
        text = template
        replacements = {
            '@PACKAGE_NAME@': package,
            '@VERSION@': version,
            '@ARCH@': arch,
            '@DESCRIPTION@': row['description'],
            '@BINARY_PATH@': str(binary_path),
            '@BINARY_NAME@': binary,
            '@SERVICE_FILE_ENTRY@': service_entry,
            '@SCRIPTS_TABLE@': scripts_table,
        }
        for old, new in replacements.items():
            text = text.replace(old, new)
        manifest_path = manifest_dir / f'{package}.toml'
        manifest_path.write_text(text)
        out.write(f'{package}\t{manifest_path}\n')
PY

printf 'Rendered %s manifests in %s\n' "$(wc -l < "$MANIFESTS_FILE")" "$MANIFEST_DIR"
