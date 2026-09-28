#!/usr/bin/env bash
# Cross-build the X.Org evdev input module for explicit /dev/input/event devices.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xf86-input-evdev/build.sh'

version=2.11.0
archive=xf86-input-evdev-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/driver/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg@lists.x.org/msg07808.html
sha256=730022de934cc366bb12439daf202a7bfff52a028cf4573e457642e25a071315
sha512=ccd3727d9726565259a81db1c238aba7e414292c3f91e182c048845ac3caf1705c2b16ff1775f3b35ecb3b7088903257085bc90a20265641ccde05b2fc6966df

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
    xkbcomp-1.5.0.nspkg
    zlib-1.3.2.nspkg
    libfontenc-1.1.9.nspkg
    libxfont2-2.0.9.nspkg
    libpciaccess-0.19.nspkg
    libdrm-2.4.134.nspkg
    libxcvt-0.1.3.nspkg
    libsha1-0.3.nspkg
    pixman-0.46.4.nspkg
    libxkbfile-1.2.0.nspkg
    xorg-server-21.1.24.nspkg
    libevdev-1.13.7.nspkg
    mtdev-1.1.7.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/xf86-input-evdev-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/xorg-server.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/libevdev.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/mtdev.pc" &&
   -f "$sysroot/usr/include/xorg/xf86.h" ]] ||
    die 'Xorg/evdev prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/xf86-input-evdev-$version"

# The release tarball's generated configure makes libudev mandatory although
# src/evdev.c has a no-libudev path. NekoOS Xorg intentionally disables udev;
# remove only that generated pkg-config probe, leaving HAVE_LIBUDEV undefined.
python3 - "$src/configure" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
udev = 'checking for libudev'
next_dep = 'checking for libevdev >= 0.4'
if source.count(udev) != 2 or source.count(next_dep) != 2:
    raise SystemExit('unexpected xf86-input-evdev configure structure')
start = source.rfind('pkg_failed=no', 0, source.index(udev))
end = source.rfind('pkg_failed=no', 0, source.index(next_dep))
if start < 0 or end - start != 3286 or 'HAVE_LIBUDEV 1' not in source[start:end]:
    raise SystemExit('failed to locate generated libudev probe')
path.write_text(source[:start] + 'UDEV_CFLAGS=\nUDEV_LIBS=\n\n' + source[end:])
PY

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
        --enable-shared --disable-static --disable-silent-rules \
        --with-xorg-module-dir=/usr/lib/xorg/modules \
        --with-xorg-conf-dir=/usr/share/X11/xorg.conf.d \
        --with-sdkdir=/usr/include/xorg
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -name '*.la' -type f -delete
module="$stage/usr/lib/xorg/modules/input/evdev_drv.so"
[[ -f "$module" && -f "$stage/usr/lib/pkgconfig/xorg-evdev.pc" ]] ||
    die 'evdev input module or development metadata is missing.'
strip --strip-unneeded "$module"
install -Dm 644 "$src/COPYING" \
    "$stage/usr/share/licenses/xf86-input-evdev/COPYING"

dynamic="$(readelf -d "$module")"
for needed in libevdev.so.2 libmtdev.so.1 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "evdev module is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libudev.so.' <<< "$dynamic"; then
    die 'evdev module contains a host or unwanted libudev dependency.'
fi
if strings "$module" | grep -F "$root/" >/dev/null; then
    die 'evdev module contains an absolute build path.'
fi

package="$root/build/system-packages/xf86-input-evdev-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xf86-input-evdev --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'xorg-server>=21.1.24' --depends 'libevdev>=1.13.7' \
    --depends 'mtdev>=1.1.7' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'XF86_INPUT_EVDEV_PACKAGE_READY: %s\n' "$package"
