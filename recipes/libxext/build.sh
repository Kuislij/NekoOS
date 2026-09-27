#!/usr/bin/env bash
# Cross-build the common X11 extension library against NekoOS musl and Xlib.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxext/build.sh'

version=1.3.7
archive=libXext-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg@lists.x.org/msg08238.html
sha256=6c643c7035cdacf67afd68f25d01b90ef889d546c9fcd7c0adf7c2cf91e3a32d
sha512=09cd230da472e87e4fdbc9b0f83a9181cc44af04c06fa4a7d8aa405e0f8551d3ac3a4b379249c44d97e1025b60d1c52f8ca13817eed0206e2bf3d66a55d89701

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
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/libxext-$version"
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
   -f "$sysroot/usr/share/pkgconfig/xextproto.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/x11.pc" &&
   -f "$sysroot/usr/include/X11/Xlib.h" ]] ||
    die 'X11 prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libXext-$version"
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
        --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete
strip --strip-unneeded "$stage/usr/lib/libXext.so.6.4.0"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxext/COPYING"

library="$(find "$stage/usr/lib" -maxdepth 1 -type f -name 'libXext.so.6.*' -print -quit)"
[[ -n "$library" && -L "$stage/usr/lib/libXext.so" &&
   -L "$stage/usr/lib/libXext.so.6" &&
   -f "$stage/usr/include/X11/extensions/Xext.h" &&
   -f "$stage/usr/lib/pkgconfig/xext.pc" ]] ||
    die 'libXext runtime or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libXext.so.6]' <<< "$dynamic" ||
    die 'libXext SONAME is wrong.'
for needed in libX11.so.6 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libXext is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libXext contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libXext contains an absolute build path.'
fi

package="$root/build/system-packages/libxext-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxext --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'libx11>=1.8.13' --depends 'xorgproto>=2025.1' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXEXT_PACKAGE_READY: %s\n' "$package"
