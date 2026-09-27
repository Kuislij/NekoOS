#!/usr/bin/env bash
# Build the X Display Manager Control Protocol library against NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxdmcp/build.sh'

version=1.1.5
archive=libXdmcp-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://lists.x.org/archives/xorg-announce/2024-March/003467.html
sha256=d8a5222828c3adab70adf69a5583f1d32eb5ece04304f7f8392b6a353aa2228c
sha512=d7a1d70a58b7d34ddd01a91d3ccbc086a36626b7081cfcbb150d24288c6adad612b042ba7ea63a218595afb2ee04384c0f8ba84ee3c6bd29913724b54e898d83
source_file="$root/cache/sources/$archive"
[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
proto="$root/build/system-packages/xorgproto-2025.1.nspkg"
[[ -f "$proto" ]] || die 'Build xorgproto first (bash recipes/xorgproto/build.sh).'
python3 "$root/tools/system_package.py" verify "$proto" >/dev/null

if [[ ! -f "$source_file" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        -o "$source_file.part" "$url"
    printf '%s  %s\n' "$sha256" "$source_file.part" | sha256sum -c -
    mv -- "$source_file.part" "$source_file"
fi
printf '%s  %s\n' "$sha256" "$source_file" | sha256sum -c -
printf '%s  %s\n' "$sha512" "$source_file" | sha512sum -c -

work="$root/build/system-package-build/libxdmcp-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
python3 "$root/tools/system_package.py" install "$proto" --root "$work/sysroot" >/dev/null
[[ -f "$work/sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$work/sysroot/usr/include/X11/X.h" ]] || die 'xorgproto install is incomplete.'
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libXdmcp-$version"
stage="$work/stage"

# Generated configure needs only the xproto pkg-config flags, supplied from
# the verified xorgproto sysroot without a host-global pkg-config install.
(
    cd "$work/build"
    PKG_CONFIG=/bin/false \
    XDMCP_CFLAGS="-I$work/sysroot/usr/include" XDMCP_LIBS=' ' \
    CC="$root/scripts/host-musl-gcc.sh" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
        --enable-shared --disable-static --disable-docs --disable-unit-tests \
        --without-xmlto
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxdmcp/COPYING"
rm -- "$stage/usr/lib/libXdmcp.la"

library="$stage/usr/lib/libXdmcp.so.6.0.0"
[[ -f "$library" ]] || die 'libXdmcp shared library was not staged.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'libXdmcp is not linked against musl.'
grep -Fq 'Library soname: [libXdmcp.so.6]' <<< "$dynamic" || die 'libXdmcp SONAME is wrong.'
! grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" || die 'libXdmcp has a runtime build path.'
[[ "$(readlink "$stage/usr/lib/libXdmcp.so.6")" == 'libXdmcp.so.6.0.0' &&
   "$(readlink "$stage/usr/lib/libXdmcp.so")" == 'libXdmcp.so.6.0.0' ]] ||
    die 'libXdmcp shared-library symlink chain is wrong.'
[[ -f "$stage/usr/include/X11/Xdmcp.h" &&
   -f "$stage/usr/lib/pkgconfig/xdmcp.pc" ]] || die 'libXdmcp development files are missing.'

package="$root/build/system-packages/libxdmcp-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxdmcp --version "$version" --arch x86_64 \
    --license MIT-open-group --source-sha256 "$sha256" --depends 'xorgproto>=2025.1' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXDMCP_PACKAGE_READY: %s\n' "$package"
