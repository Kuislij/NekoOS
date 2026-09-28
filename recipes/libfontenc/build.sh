#!/usr/bin/env bash
# Cross-build X.Org font encodings against the NekoOS musl and zlib packages.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libfontenc/build.sh'

version=1.1.9
archive=libfontenc-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org announcement: https://www.mail-archive.com/xorg@lists.x.org/msg08251.html
sha256=9d8392705cb10803d5fe1d27d236cbab3f664e26841ce01916bbbe430cf273e2
sha512=19050c4c9ea1143b555b92faec641fd6b4976de463ad1fb67d20a7bf2f610bbc3debd3c65925cd8329691a9fb0435d004a05b6486e1dc600719e8c479812b912

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
for tool in curl sha256sum sha512sum tar make python3 readelf strip strings; do
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
printf '%s  %s\n' "$sha512" "$source_file" | sha512sum -c -

proto="$root/build/system-packages/xorgproto-2025.1.nspkg"
zlib="$root/build/system-packages/zlib-1.3.2.nspkg"
for package in "$proto" "$zlib"; do
    [[ -f "$package" ]] || die "Missing prerequisite system package: $package"
    python3 "$root/tools/system_package.py" verify "$package" >/dev/null
done

work="$root/build/system-package-build/libfontenc-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "$proto" "$zlib" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$sysroot/usr/include/X11/X.h" &&
   -f "$sysroot/usr/include/zlib.h" &&
   -f "$sysroot/usr/lib/pkgconfig/zlib.pc" ]] ||
    die 'Protocol or zlib prerequisite package did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libfontenc-$version"
(
    cd "$work/build"
    export PKG_CONFIG="$pkgconf"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    CPPFLAGS="-I$sysroot/usr/include" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib" \
    CC="$root/scripts/host-musl-gcc.sh" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
        --with-fontrootdir=/usr/share/fonts/X11 \
        --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete
strip --strip-unneeded "$stage/usr/lib/libfontenc.so.1.0.0"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libfontenc/COPYING"

library="$stage/usr/lib/libfontenc.so.1.0.0"
[[ -f "$library" && -L "$stage/usr/lib/libfontenc.so" &&
   -L "$stage/usr/lib/libfontenc.so.1" &&
   -f "$stage/usr/include/X11/fonts/fontenc.h" &&
   -f "$stage/usr/lib/pkgconfig/fontenc.pc" ]] ||
    die 'libfontenc runtime or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libfontenc.so.1]' <<< "$dynamic" ||
    die 'libfontenc SONAME is wrong.'
for needed in libc.so libz.so.1; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libfontenc is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libfontenc contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libfontenc contains an absolute build path.'
fi

package="$root/build/system-packages/libfontenc-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libfontenc --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'xorgproto>=2025.1' --depends 'zlib>=1.3.2' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBFONTENC_PACKAGE_READY: %s\n' "$package"
