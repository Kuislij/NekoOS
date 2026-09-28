#!/usr/bin/env bash
# Cross-build the XKB file parser used by Xorg and keyboard utilities.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxkbfile/build.sh'

version=1.2.0
archive=libxkbfile-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg-announce@lists.x.org/msg01871.html
sha256=7f71884e5faf56fb0e823f3848599cf9b5a9afce51c90982baeb64f635233ebf
sha512=772035b6bc1d692e8141e095fc2a8cf2ba7daed1d7148def862103160e0d7706f46865367befbbe4c777e7311b224d2cd4474f399d747b122dd395deac3e7cb7

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
meson_source="$root/build/host-tools/meson-1.10.1"
meson=(python3 "$meson_source/meson.py")
[[ -f "$meson_source/meson.py" && "$("${meson[@]}" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/xorgproto/build.sh).'
for tool in curl sha256sum sha512sum tar python3 ninja ar strip readelf strings; do
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

work="$root/build/system-package-build/libxkbfile-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/share/pkgconfig/kbproto.pc" &&
   -f "$sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/x11.pc" &&
   -f "$sysroot/usr/include/X11/XKBlib.h" &&
   -f "$sysroot/usr/lib/libX11.so.6.4.0" ]] ||
    die 'XKB/X11 prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libxkbfile-$version"

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
    "${meson[@]}" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared
    "${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
)

library="$stage/usr/lib/libxkbfile.so.1.0.2"
[[ -f "$library" && -L "$stage/usr/lib/libxkbfile.so" &&
   -L "$stage/usr/lib/libxkbfile.so.1" &&
   -f "$stage/usr/include/X11/extensions/XKBfile.h" &&
   -f "$stage/usr/lib/pkgconfig/xkbfile.pc" ]] ||
    die 'libxkbfile runtime or development files are missing.'
strip --strip-unneeded "$library"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxkbfile/COPYING"

dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libxkbfile.so.1]' <<< "$dynamic" ||
    die 'libxkbfile SONAME is wrong.'
for needed in libX11.so.6 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libxkbfile is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libxkbfile contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libxkbfile contains an absolute build path.'
fi

package="$root/build/system-packages/libxkbfile-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxkbfile --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'libx11>=1.8.13' --depends 'xorgproto>=2025.1' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXKBFILE_PACKAGE_READY: %s\n' "$package"
