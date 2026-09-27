#!/usr/bin/env bash
# Build pinned upstream components that become part of the NekoOS /usr tree.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash scripts/build-system-packages.sh'

bash "$root/recipes/pixman/build.sh"
python3 "$root/tools/system_package.py" verify \
    "$root/build/system-packages/pixman-0.46.4.nspkg"
