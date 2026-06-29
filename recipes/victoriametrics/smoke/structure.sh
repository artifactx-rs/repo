#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$script_dir/../../.." && pwd)
version=${1:?version required}
"$root/helpers/smoke-package-structure.sh" victoriametrics "$version"
