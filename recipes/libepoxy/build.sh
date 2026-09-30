#!/usr/bin/env bash
# Build the GL dispatch ABI used by GTK's X11 backend; rendering stays software.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libepoxy/build.sh'

version=1.5.10
archive=libepoxy-$version.tar.xz
url=https://download.gnome.org/sources/libepoxy/1.5/$archive
# Published beside the official release archive.
sha256=072cda4b59dd098bba8c2363a6247299db1fa89411dc221c8b81b8ee8192e623
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$root/build/host-musl-gcc.specs" && -x "$pkgconf" && -f "$meson" ]] ||
    die 'Build the pinned musl toolchain and host tools first (bash os build).'
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
prerequisites=(libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
               libx11-1.8.13.nspkg xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done
work="$root/build/system-package-build/libepoxy-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" --root "$sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libepoxy-$version"
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
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dglx=yes -Degl=no -Dx11=true -Dtests=false -Ddocs=false
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libepoxy/COPYING"
library="$(readlink -f "$stage/usr/lib/libepoxy.so.0")"
[[ -f "$library" && -L "$stage/usr/lib/libepoxy.so" &&
   -f "$stage/usr/include/epoxy/gl.h" && -f "$stage/usr/include/epoxy/glx.h" &&
   -f "$stage/usr/lib/pkgconfig/epoxy.pc" ]] || die 'Libepoxy development files are missing.'
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libepoxy.so.0]' <<< "$dynamic" || die 'Wrong libepoxy SONAME.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'Libepoxy lacks musl linkage.'
if grep -Eq '\((RPATH|RUNPATH)\)|libc.so.6' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'Libepoxy contains a host dependency or build path.'
fi
package="$root/build/system-packages/libepoxy-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libepoxy --version "$version" --arch x86_64 \
    --license MIT --source-sha256 "$sha256" \
    --depends 'libx11>=1.8.13' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBEPOXY_PACKAGE_READY: %s\n' "$package"
