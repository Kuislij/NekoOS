#!/usr/bin/env bash
# Cross-build the XKB keymap compiler with host Bison and NekoOS X11 libraries.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xkbcomp/build.sh'

version=1.5.0
archive=xkbcomp-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/app/$archive
# X.Org release announcement: https://lists.x.org/archives/xorg-announce/2025-December/003645.html
sha256=2ac31f26600776db6d9cd79b3fcd272263faebac7eb85fb2f33c7141b8486060
sha512=d8ef4906261251e2600b3650660fbe88ed99a44694f1e59b433e0811f1ab5234c4f2f0b3647fa5372fb0f46b56eac60c0219a762bf1af0ab06226b63e4a6b081

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
meson_source="$root/build/host-tools/meson-1.10.1"
meson=(python3 "$meson_source/meson.py")
[[ -f "$meson_source/meson.py" && "$("${meson[@]}" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/xorgproto/build.sh).'
for tool in curl sha256sum sha512sum tar python3 ninja ar strip readelf strings bison; do
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
    libxkbfile-1.2.0.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/xkbcomp-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/x11.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/xkbfile.pc" &&
   -f "$sysroot/usr/include/X11/extensions/XKBfile.h" &&
   -f "$sysroot/usr/lib/libxkbfile.so.1.0.2" ]] ||
    die 'XKB/X11 prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/xkbcomp-$version"

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
        --buildtype=release --wrap-mode=nofallback \
        -Dxkb-config-root=/usr/share/X11/xkb
    "${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
)

binary="$stage/usr/bin/xkbcomp"
[[ -f "$binary" && -f "$stage/usr/lib/pkgconfig/xkbcomp.pc" ]] ||
    die 'xkbcomp executable or pkg-config metadata is missing.'
strip --strip-unneeded "$binary"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/xkbcomp/COPYING"

interpreter="$(readelf -l "$binary")"
grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' <<< "$interpreter" ||
    die 'xkbcomp does not use the NekoOS musl loader.'
dynamic="$(readelf -d "$binary")"
for needed in libxkbfile.so.1 libX11.so.6 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "xkbcomp is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'xkbcomp contains a host runtime dependency or build path.'
fi
if strings "$binary" | grep -F "$root/" >/dev/null; then
    die 'xkbcomp contains an absolute build path.'
fi

package="$root/build/system-packages/xkbcomp-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xkbcomp --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'libxkbfile>=1.2.0' --depends 'libx11>=1.8.13' \
    --depends 'xorgproto>=2025.1' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'XKBCOMP_PACKAGE_READY: %s\n' "$package"
