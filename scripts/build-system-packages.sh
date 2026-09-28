#!/usr/bin/env bash
# Build pinned upstream components that become part of the NekoOS /usr tree.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
source "$root/configs/system-packages.sh"
(( $# == 0 )) || die 'Usage: bash scripts/build-system-packages.sh'

bash "$root/recipes/pixman/build.sh"
bash "$root/recipes/xorgproto/build.sh"
bash "$root/recipes/xtrans/build.sh"
bash "$root/recipes/zlib/build.sh"
bash "$root/recipes/libxau/build.sh"
bash "$root/recipes/libxdmcp/build.sh"
bash "$root/recipes/xcb-proto/build.sh"
bash "$root/recipes/pkgconf/build.sh"
bash "$root/recipes/libxcb/build.sh"
bash "$root/recipes/libx11/build.sh"
bash "$root/recipes/libxext/build.sh"
bash "$root/recipes/libxkbfile/build.sh"
bash "$root/recipes/xkbcomp/build.sh"
bash "$root/recipes/xkeyboard-config/build.sh"
bash "$root/recipes/libfontenc/build.sh"
bash "$root/recipes/libxfont2/build.sh"
bash "$root/recipes/font-misc-misc/build.sh"
bash "$root/recipes/libxcvt/build.sh"
bash "$root/recipes/libpciaccess/build.sh"
bash "$root/recipes/libdrm/build.sh"
bash "$root/recipes/libsha1/build.sh"
bash "$root/recipes/xorg-server/build.sh"
bash "$root/recipes/libevdev/build.sh"
bash "$root/recipes/mtdev/build.sh"
bash "$root/recipes/xf86-input-evdev/build.sh"
for package in "${system_package_archives[@]}"; do
    python3 "$root/tools/system_package.py" verify \
        "$root/build/system-packages/$package"
done
