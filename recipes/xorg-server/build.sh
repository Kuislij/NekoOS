#!/usr/bin/env bash
# Cross-build a software-rendered Xorg server and DRM modesetting DDX for NekoOS.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xorg-server/build.sh'

version=21.1.24
archive=xorg-server-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/xserver/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg@lists.x.org/msg08314.html
sha256=1a4eb36ca65cc3b1b936566d677a9786e13c11cd5806e951ac55f3f5ce3984af
sha512=f51372b04fe21632fc778ff240705161ed2dccc0114dbe3ee25156d8ac85ec945e2ac05d8638bc7d8d54bad4dfc89cb26b6bd2058b7804d54ab7179e1ac2eb13

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
    libxext-1.3.7.nspkg
    libxkbfile-1.2.0.nspkg
    xkbcomp-1.5.0.nspkg
    zlib-1.3.2.nspkg
    libfontenc-1.1.9.nspkg
    libxfont2-2.0.9.nspkg
    libpciaccess-0.19.nspkg
    libdrm-2.4.134.nspkg
    libxcvt-0.1.3.nspkg
    pixman-0.46.4.nspkg
    libsha1-0.3.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/xorg-server-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/pixman-1.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/xfont2.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/libdrm.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/libxcvt.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/pciaccess.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/libsha1.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/xkbfile.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/xkbcomp.pc" ]] ||
    die 'Xorg prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/xorg-server-$version"

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
        -Dxorg=true -Dxephyr=false -Dxnest=false -Dxvfb=false \
        -Dxwin=false -Dxquartz=false -Dglamor=false -Dglx=false \
        -Ddri1=false -Ddri2=true -Ddri3=false -Ddrm=true \
        -Dudev=false -Dudev_kms=false -Dsystemd_logind=false -Dhal=false \
        -Dint10=false -Dvgahw=false -Dlinux_apm=false -Dlinux_acpi=false \
        -Dxf86-input-inputtest=false -Dsecure-rpc=false \
        -Dxdmcp=false -Dxdm-auth-1=false -Dxselinux=false \
        -Dxv=false -Dxvmc=false -Dagp=false \
        -Dsha1=libsha1 -Ddocs=false -Ddevel-docs=false -Ddocs-pdf=false \
        -Ddefault_font_path=/usr/share/fonts/X11/misc \
        -Dxkb_dir=/usr/share/X11/xkb -Dxkb_output_dir=/tmp/xkb \
        -Dxkb_bin_dir=/usr/bin -Dlog_dir=/tmp
    "${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
)

binary="$stage/usr/bin/Xorg"
modesetting="$stage/usr/lib/xorg/modules/drivers/modesetting_drv.so"
[[ -f "$binary" && -f "$modesetting" ]] ||
    die 'Xorg server or modesetting driver is missing.'
strip --strip-unneeded "$binary"
while IFS= read -r -d '' shared; do
    strip --strip-unneeded "$shared"
    dynamic="$(readelf -d "$shared")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "Xorg module contains a host dependency or build path: $shared"
    fi
done < <(find "$stage/usr/lib/xorg/modules" -type f -name '*.so' -print0)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/xorg-server/COPYING"

interpreter="$(readelf -l "$binary")"
grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' <<< "$interpreter" ||
    die 'Xorg does not use the NekoOS musl loader.'
dynamic="$(readelf -d "$binary")"
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'Xorg contains a host runtime dependency or build path.'
fi
for elf in "$binary" "$modesetting"; do
    if strings "$elf" | grep -F "$root/" >/dev/null; then
        die "Xorg binary contains an absolute build path: $elf"
    fi
done

package="$root/build/system-packages/xorg-server-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xorg-server --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'xorgproto>=2025.1' --depends 'xtrans>=1.6.0' \
    --depends 'pixman>=0.46.4' --depends 'libxkbfile>=1.2.0' \
    --depends 'libxfont2>=2.0.9' --depends 'libxcvt>=0.1.3' \
    --depends 'libdrm>=2.4.134' --depends 'libpciaccess>=0.19' \
    --depends 'libsha1>=0.3' --depends 'xkbcomp>=1.5.0' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'XORG_SERVER_PACKAGE_READY: %s\n' "$package"
