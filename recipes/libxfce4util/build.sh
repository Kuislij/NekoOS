#!/usr/bin/env bash
# Cross-build the first Xfce library against packaged NekoOS GLib and musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxfce4util/build.sh'

version=4.20.1
archive=libxfce4util-$version.tar.bz2
url=https://archive.xfce.org/src/xfce/libxfce4util/4.20/$archive
sha256=84bfc4daab9e466193540c3665eee42b2cf4d24e3f38fc3e8d1e0a2bebe3b8f1
sha512=b9eecac47245c37a46f8e381ed5c672233aae3a78cae8ac0b25a79598847210267172cd03d64d5f4d0405640608f4885092fd62431914b58a930c7b401067268

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
for tool in curl sha256sum sha512sum tar make python3 readelf strip strings find; do
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
    libffi-3.5.2.nspkg
    pcre2-10.48.nspkg
    zlib-1.3.2.nspkg
    glib-2.84.4.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/libxfce4util-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/glib-2.0.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/gobject-2.0.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/gio-2.0.pc" &&
   -f "$sysroot/usr/include/glib-2.0/glib.h" &&
   -f "$sysroot/usr/lib/libglib-2.0.so.0" ]] ||
    die 'Packaged GLib development files are incomplete.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libxfce4util-$version"

# The release archive includes configure and generated visibility sources.
# Disable optional bindings, documentation and translations until their host
# generators have separate, verified recipes.
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
        --enable-shared --disable-static --disable-nls \
        --enable-introspection=no --enable-vala=no --disable-gtk-doc
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -name '*.la' -type f -delete
rm -rf -- "$stage/usr/share/man" "$stage/usr/share/gtk-doc"
install -Dm 644 "$src/COPYING" \
    "$stage/usr/share/licenses/libxfce4util/COPYING"

library="$stage/usr/lib/libxfce4util.so.7.0.0"
header="$stage/usr/include/xfce4/libxfce4util/libxfce4util.h"
pc="$stage/usr/lib/pkgconfig/libxfce4util-1.0.pc"
kiosk="$stage/usr/sbin/xfce4-kiosk-query"
[[ -f "$library" && -L "$stage/usr/lib/libxfce4util.so.7" &&
   -L "$stage/usr/lib/libxfce4util.so" && -f "$header" &&
   -f "$pc" && -f "$kiosk" ]] ||
    die 'libxfce4util shared library, headers, pkg-config file or utility is missing.'
strip --strip-unneeded "$library" "$kiosk"

dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libxfce4util.so.7]' <<< "$dynamic" ||
    die 'libxfce4util SONAME is wrong.'
grep -Fq 'Shared library: [libglib-2.0.so.0]' <<< "$dynamic" ||
    die 'libxfce4util is not linked against packaged GLib.'
for elf in "$library" "$kiosk"; do
    dynamic="$(readelf -d "$elf")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "Xfce binary contains a host dependency or build path: $elf"
    fi
    if strings "$elf" | grep -F "$root/" >/dev/null; then
        die "Xfce binary contains an absolute build path: $elf"
    fi
done
readelf -l "$kiosk" |
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' ||
    die 'xfce4-kiosk-query does not use the NekoOS musl loader.'

package="$root/build/system-packages/libxfce4util-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxfce4util --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'glib>=2.84.4' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXFCE4UTIL_PACKAGE_READY: %s\n' "$package"
