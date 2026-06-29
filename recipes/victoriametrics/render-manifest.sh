#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../.." && pwd)
# shellcheck source=/dev/null
. "$root/work/victoriametrics/current.env"

test -x "$BINARY_PATH"
test -f "$SERVICE_PATH"

postinst="$script_dir/scripts/postinst.sh"
postrm="$script_dir/scripts/postrm.sh"
test -x "$postinst"
test -x "$postrm"

python3 - <<'PY' "$script_dir/arx-pack.toml.in" "$MANIFEST_PATH" "$VERSION" "$BINARY_PATH" "$SERVICE_PATH" "$postinst" "$postrm"
import pathlib, sys
src, dest, version, binary, service, postinst, postrm = sys.argv[1:]
text = pathlib.Path(src).read_text()
replacements = {
    '@VERSION@': version,
    '@BINARY_PATH@': binary,
    '@SERVICE_PATH@': service,
    '@POSTINST_PATH@': postinst,
    '@POSTRM_PATH@': postrm,
}
for old, new in replacements.items():
    text = text.replace(old, new)
pathlib.Path(dest).write_text(text)
PY

printf 'Rendered %s\n' "$MANIFEST_PATH"
