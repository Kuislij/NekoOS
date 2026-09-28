#!/usr/bin/env bash
# Build the X.Org bitmap-font converter for the Linux build host only.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/bdftopcf/build.sh'

version=1.1.2
archive=bdftopcf-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/util/$archive
sha256=bc60be5904330faaa3ddd2aed7874bee2f29e4387c245d6787552f067eb0523a
sha512=b3dde8d73084b7ec23ea47491321d12fa8f4a0a9ce0f61f2f89460fdc98f05d135ba11d8588d9debb8c2639ac68a7434a0cf80d9d548cd7328cbcb2339b4c0a6

for tool in curl sha256sum sha512sum tar make gcc python3; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first.'
xorgproto="$root/build/system-packages/xorgproto-2025.1.nspkg"
[[ -f "$xorgproto" ]] || die 'Build xorgproto before bdftopcf.'
python3 "$root/tools/system_package.py" verify "$xorgproto" >/dev/null

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

work="$root/build/host-tools/bdftopcf-$version"
[[ ! -L "$root/build/host-tools" && ! -L "$work" ]] ||
    die 'Host tool work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/sysroot"
python3 "$root/tools/system_package.py" install "$xorgproto" \
    --root "$work/sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/bdftopcf-$version"
(
    cd "$work/build"
    export PKG_CONFIG="$pkgconf"
    export PKG_CONFIG_LIBDIR="$work/sysroot/usr/share/pkgconfig"
    unset PKG_CONFIG_PATH PKG_CONFIG_SYSROOT_DIR
    CPPFLAGS="-I$work/sysroot/usr/include" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    CC=gcc "$src/configure" --prefix="$work/install" \
        --disable-dependency-tracking
    make -j "${JOBS:-4}"
    make install
)
converter="$work/install/bin/bdftopcf"
[[ -x "$converter" ]] || die 'Host bdftopcf was not installed.'
printf 'HOST_BDFTOPCF_READY: %s\n' "$converter"
