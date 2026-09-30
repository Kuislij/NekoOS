#!/usr/bin/env bash
# Build the Unicode bidirectional algorithm library for NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/fribidi/build.sh'

version=1.0.16
archive=fribidi-$version.tar.xz
url=https://github.com/fribidi/fribidi/releases/download/v$version/$archive
sha256=1b1cde5b235d40479e91be2f0e88a309e3214c8ab470ec8a2744d82a5a9ea05c
[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 && -f "$meson" &&
   "$(python3 "$meson" --version)" == 1.10.1 ]] || die 'Build the pinned host pkgconf and Meson first.'
for tool in curl sha256sum tar python3 ninja ar strip readelf strings find; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

source_file="$root/cache/sources/$archive"
if [[ ! -f "$source_file" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        -o "$source_file.part" "$url"
    printf '%s  %s\n' "$sha256" "$source_file.part" | sha256sum -c -
    mv -- "$source_file.part" "$source_file"
fi
printf '%s  %s\n' "$sha256" "$source_file" | sha256sum -c -
work="$root/build/system-package-build/fribidi-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] || die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" "$root/build/system-packages"
stage="$work/stage"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/fribidi-$version"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
(
    export PKG_CONFIG_LIBDIR="$work/sysroot/usr/lib/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$work/sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Ddocs=false -Dtests=false -Dbin=false
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/fribidi/COPYING"
library="$(readlink -f "$stage/usr/lib/libfribidi.so.0")"
[[ -f "$library" && -L "$stage/usr/lib/libfribidi.so" &&
   -f "$stage/usr/include/fribidi/fribidi.h" && -f "$stage/usr/lib/pkgconfig/fribidi.pc" ]] ||
    die 'FriBidi library or development files are missing.'
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libfribidi.so.0]' <<< "$dynamic" || die 'FriBidi SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'FriBidi is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)|Shared library: \[libc.so.6\]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'FriBidi contains a host runtime dependency or build path.'
fi
"$root/scripts/host-musl-gcc.sh" -I"$stage/usr/include/fribidi" \
    -L"$stage/usr/lib" "$root/recipes/fribidi/smoke.c" -lfribidi -o "$work/fribidi-smoke"
"$root/build/toolchain-root/usr/lib/libc.so" --library-path "$stage/usr/lib" "$work/fribidi-smoke"
package="$root/build/system-packages/fribidi-$version.nspkg"
python3 "$root/tools/system_package.py" build --root "$stage" --name fribidi \
    --version "$version" --arch x86_64 --license LGPL-2.1-or-later \
    --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'FRIBIDI_PACKAGE_READY: %s\n' "$package"
