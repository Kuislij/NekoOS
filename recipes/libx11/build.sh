#!/usr/bin/env bash
# Cross-build upstream Xlib against verified NekoOS musl/X11 packages.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libx11/build.sh'

version=1.8.13
archive=libX11-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg@lists.x.org/msg08248.html
sha256=69606f485c2c07c14ef64f75b7bb326d48587af33795d9ab3e607c0b5f94f11c
sha512=4c4a098eaff09a51309f3f322bc435ccd022c8f753974eb2650b60e42b737077ca0fde0df82b53f4ba8ed2388bbc8cb59ba66cc9946ae2b5907d7d1a9580e03d

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
xau="$root/build/system-packages/libxau-1.0.12.nspkg"
xdmcp="$root/build/system-packages/libxdmcp-1.1.5.nspkg"
xtrans="$root/build/system-packages/xtrans-1.6.0.nspkg"
xcb="$root/build/system-packages/libxcb-1.17.0.nspkg"
for package in "$proto" "$xau" "$xdmcp" "$xtrans" "$xcb"; do
    [[ -f "$package" ]] || die "Missing prerequisite system package: $package"
    python3 "$root/tools/system_package.py" verify "$package" >/dev/null
done

work="$root/build/system-package-build/libx11-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "$proto" "$xau" "$xdmcp" \
    "$xtrans" "$xcb" --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/include/X11/X.h" &&
   -f "$sysroot/usr/include/X11/keysymdef.h" &&
   -f "$sysroot/usr/include/xcb/xcb.h" &&
   -f "$sysroot/usr/lib/libxcb.so.1.1.0" &&
   -f "$sysroot/usr/share/pkgconfig/xtrans.pc" ]] ||
    die 'Prerequisite X11 packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libX11-$version"

# The release tarball includes its generated configure script; util-macros is
# needed only if regenerating Autotools files. makekeys is built for the build
# host by CC_FOR_BUILD, while all installed libraries use the NekoOS musl CC.
(
    cd "$work/build"
    export PKG_CONFIG="$pkgconf"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    CPPFLAGS="-I$sysroot/usr/include" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib" \
    CC="$root/scripts/host-musl-gcc.sh" CC_FOR_BUILD=gcc \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
        --enable-shared --disable-static --disable-specs \
        --with-keysymdefdir="$sysroot/usr/include/X11" \
        --disable-loadable-i18n
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

# Libtool archives encode staging paths and are not consumed by guest programs.
find "$stage/usr/lib" -name '*.la' -type f -delete
# The guest has no man-page reader yet, and keeping debug symbols in this large
# client library would needlessly consume the bounded early-boot initramfs.
rm -rf -- "$stage/usr/share/man"
strip --strip-unneeded "$stage/usr/lib/libX11.so.6.4.0" \
    "$stage/usr/lib/libX11-xcb.so.1.0.0"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libx11/COPYING"

library="$stage/usr/lib/libX11.so.6.4.0"
[[ -f "$library" && -L "$stage/usr/lib/libX11.so" &&
   -L "$stage/usr/lib/libX11.so.6" &&
   -f "$stage/usr/include/X11/Xlib.h" &&
   -f "$stage/usr/lib/pkgconfig/x11.pc" &&
   -d "$stage/usr/share/X11/locale" ]] ||
    die 'libX11 shared library, development files or locale data are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libX11.so.6]' <<< "$dynamic" ||
    die 'libX11 SONAME is wrong.'
for needed in libc.so libxcb.so.1; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libX11 is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic"; then
    die 'libX11 contains a build-path runtime search path.'
fi
if grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libX11 is linked against host glibc.'
fi
xcb_library="$stage/usr/lib/libX11-xcb.so.1.0.0"
[[ -f "$xcb_library" && -L "$stage/usr/lib/libX11-xcb.so.1" ]] ||
    die 'libX11-xcb shared library is missing.'
xcb_dynamic="$(readelf -d "$xcb_library")"
grep -Fq 'Library soname: [libX11-xcb.so.1]' <<< "$xcb_dynamic" ||
    die 'libX11-xcb SONAME is wrong.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$xcb_dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$xcb_dynamic"; then
    die 'libX11-xcb contains a host runtime dependency or build path.'
fi
for shared in "$library" "$xcb_library"; do
    if strings "$shared" | grep -F "$root/" >/dev/null; then
        die "Xlib shared library contains an absolute build path: $shared"
    fi
done

package="$root/build/system-packages/libx11-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libx11 --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'xorgproto>=2025.1' --depends 'xtrans>=1.6.0' \
    --depends 'libxcb>=1.17.0' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBX11_PACKAGE_READY: %s\n' "$package"
