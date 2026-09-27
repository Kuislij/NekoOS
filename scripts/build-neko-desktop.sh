#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 1 )) || die 'Usage: bash scripts/build-neko-desktop.sh OUTPUT'
[[ -s "$root/build/host-musl-gcc.specs" ]] || die 'Build the NekoOS toolchain first.'
"$root/scripts/host-musl-gcc.sh" -std=c11 -O2 -Wall -Wextra -Werror -static \
    -o "$1" "$root/rootfs/usr/bin/neko-desktop.c" \
    "$root/rootfs/usr/bin/neko-windows.c" \
    "$root/rootfs/usr/bin/neko-files.c" \
    "$root/rootfs/usr/bin/neko-system.c"
if readelf -l "$1" | grep -q INTERP; then
    die 'Neko desktop must be statically linked.'
fi
echo "NEKO_DESKTOP_BUILT: $1"
