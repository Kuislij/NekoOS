#!/usr/bin/env bash
# Build the NekoOS GTK3 welcome/notes app against packaged guest libraries.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 1 || $# == 2 )) || die 'Usage: bash scripts/build-gtk-welcome.sh OUTPUT [SYSROOT]'
output="$1"
sysroot="${2:-$root/build/rootfs}"
[[ -s "$root/build/host-musl-gcc.specs" ]] || die 'Build the NekoOS toolchain first.'
[[ -f "$sysroot/usr/lib/pkgconfig/gtk+-3.0.pc" ]] ||
    die "Packaged GTK3 development files are missing from $sysroot"
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first.'

export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$sysroot"
unset PKG_CONFIG_PATH
read -r -a gtk_cflags <<< "$("$pkgconf" --cflags gtk+-3.0)"
read -r -a gtk_libs <<< "$("$pkgconf" --libs gtk+-3.0)"
mkdir -p "$(dirname -- "$output")"
"$root/scripts/host-musl-gcc.sh" -std=c11 -O2 -Wall -Wextra -Werror \
    "-ffile-prefix-map=$root=/usr/src/nekoos" \
    "${gtk_cflags[@]}" -Wl,-rpath-link,"$sysroot/usr/lib" \
    -o "$output" "$root/src/gtk/welcome.c" "${gtk_libs[@]}"
grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
    < <(readelf -l "$output") || die 'GTK welcome app lacks the NekoOS musl interpreter.'
dynamic="$(readelf -d "$output")"
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'GTK welcome app contains a host runtime dependency or build path.'
fi
strip --strip-unneeded "$output"
printf 'NEKO_GTK_WELCOME_BUILT: %s\n' "$output"
