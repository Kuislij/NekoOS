#!/usr/bin/env bash
# Build X.Org's bitmap-font server library against NekoOS musl packages.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxfont2/build.sh'

version=2.0.9
archive=libXfont2-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org announcement: https://www.mail-archive.com/xorg@lists.x.org/msg08332.html
sha256=f042a370666815e7b941e9b7019024755bd1c6c2954afbfa515af378251799e2
sha512=ccd6d6abf6aa814a940d137813dba638f8259c3672abf00808d82df033c1026ae29d40c9068da4f112637338ad0d0fc15818a4afa9369a626c8f17e466b4fa72

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

prerequisites=(
    xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    zlib-1.3.2.nspkg
    libfontenc-1.1.9.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/libxfont2-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$sysroot/usr/share/pkgconfig/fontsproto.pc" &&
   -f "$sysroot/usr/share/pkgconfig/xtrans.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/zlib.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/fontenc.pc" &&
   -f "$sysroot/usr/include/X11/fonts/fontenc.h" ]] ||
    die 'Protocol, transport, zlib or fontenc prerequisites are incomplete.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libXfont2-$version"
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
        --enable-shared --disable-static --disable-devel-docs \
        --disable-freetype --without-bzip2 --disable-fc \
        --enable-builtins --enable-pcfformat --enable-bdfformat
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete
rm -rf -- "$stage/usr/share/man"
strip --strip-unneeded "$stage/usr/lib/libXfont2.so.2.0.0"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxfont2/COPYING"

library="$stage/usr/lib/libXfont2.so.2.0.0"
[[ -f "$library" && -L "$stage/usr/lib/libXfont2.so" &&
   -L "$stage/usr/lib/libXfont2.so.2" &&
   -f "$stage/usr/include/X11/fonts/libxfont2.h" &&
   -f "$stage/usr/lib/pkgconfig/xfont2.pc" ]] ||
    die 'libXfont2 runtime or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libXfont2.so.2]' <<< "$dynamic" ||
    die 'libXfont2 SONAME is wrong.'
for needed in libc.so libfontenc.so.1 libz.so.1; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libXfont2 is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libXfont2 contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libXfont2 contains an absolute build path.'
fi

package="$root/build/system-packages/libxfont2-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxfont2 --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'xorgproto>=2025.1' --depends 'xtrans>=1.6.0' \
    --depends 'zlib>=1.3.2' --depends 'libfontenc>=1.1.9' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXFONT2_PACKAGE_READY: %s\n' "$package"
