#!/usr/bin/env bash
# Build the X11 authorization library against the NekoOS musl toolchain.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxau/build.sh'

version=1.0.12
archive=libXau-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://lists.x.org/archives/xorg-announce/2024-December/003570.html
sha256=74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb
sha512=4bbe8796f4a14340499d5f75046955905531ea2948944dfc3d6069f8b86c1710042bfc7918d459320557883e6631359d48e6173c69c62ff572314e864ff97c5e
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

work="$root/build/system-package-build/libxau-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
python3 "$root/tools/system_package.py" install "$proto" --root "$work/sysroot" >/dev/null
[[ -f "$work/sysroot/usr/share/pkgconfig/xproto.pc" &&
   -f "$work/sysroot/usr/include/X11/X.h" ]] || die 'xorgproto install is incomplete.'
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libXau-$version"
stage="$work/stage"

# The release tarball already contains configure. Its only pkg-config module is
# xproto, whose verified headers are installed above; pass those flags directly
# because the build host does not currently ship pkg-config.
(
    cd "$work/build"
    PKG_CONFIG=/bin/false \
    XAU_CFLAGS="-I$work/sysroot/usr/include" XAU_LIBS=' ' \
    CC="$root/scripts/host-musl-gcc.sh" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
        --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxau/COPYING"
rm -- "$stage/usr/lib/libXau.la"

library="$stage/usr/lib/libXau.so.6.0.0"
[[ -f "$library" ]] || die 'libXau shared library was not staged.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'libXau is not linked against musl.'
grep -Fq 'Library soname: [libXau.so.6]' <<< "$dynamic" || die 'libXau SONAME is wrong.'
! grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" || die 'libXau has a runtime build path.'
[[ "$(readlink "$stage/usr/lib/libXau.so.6")" == 'libXau.so.6.0.0' &&
   "$(readlink "$stage/usr/lib/libXau.so")" == 'libXau.so.6.0.0' ]] ||
    die 'libXau shared-library symlink chain is wrong.'
[[ -f "$stage/usr/include/X11/Xauth.h" &&
   -f "$stage/usr/lib/pkgconfig/xau.pc" ]] || die 'libXau development files are missing.'

package="$root/build/system-packages/libxau-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxau --version "$version" --arch x86_64 \
    --license MIT-open-group --source-sha256 "$sha256" --depends 'xorgproto>=2025.1' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXAU_PACKAGE_READY: %s\n' "$package"
