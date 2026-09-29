#!/usr/bin/env bash
# Cross-build the FreeType font engine with packaged zlib and NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/freetype/build.sh'

version=2.14.3
archive=freetype-$version.tar.xz
url=https://download.savannah.gnu.org/releases/freetype/$archive
# Published by the FreeType project in its 2.14.3 release README.
sha256=36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f
sha512=43de86ea70b4b47f6efaae67f3440f65a24ffac29dc6d11203a9764e4f1a749ce1ba7645acd23525220b3ba12ddad8687b962b9f1254e2c0a86070854e85d5a0

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

zlib="$root/build/system-packages/zlib-1.3.2.nspkg"
[[ -f "$zlib" ]] || die "Missing prerequisite system package: $zlib"
python3 "$root/tools/system_package.py" verify "$zlib" >/dev/null

work="$root/build/system-package-build/freetype-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "$zlib" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/include/zlib.h" &&
   -f "$sysroot/usr/lib/pkgconfig/zlib.pc" &&
   -f "$sysroot/usr/lib/libz.so.1" ]] ||
    die 'Packaged zlib development files are incomplete.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/freetype-$version"

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
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dzlib=system -Dbzip2=disabled -Dpng=disabled \
        -Dharfbuzz=disabled -Dbrotli=disabled -Dtests=disabled -Dmmap=enabled
    "${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
)

install -Dm 644 "$src/LICENSE.TXT" \
    "$stage/usr/share/licenses/freetype/LICENSE.TXT"
install -Dm 644 "$src/docs/FTL.TXT" \
    "$stage/usr/share/licenses/freetype/FTL.TXT"
install -Dm 644 "$src/docs/GPLv2.TXT" \
    "$stage/usr/share/licenses/freetype/GPLv2.TXT"

library="$stage/usr/lib/libfreetype.so.6"
header="$stage/usr/include/freetype2/ft2build.h"
pc="$stage/usr/lib/pkgconfig/freetype2.pc"
[[ -L "$library" && -L "$stage/usr/lib/libfreetype.so" &&
   -f "$header" && -f "$stage/usr/include/freetype2/freetype/freetype.h" &&
   -f "$pc" ]] ||
    die 'FreeType shared library, headers or pkg-config file is missing.'
library="$(readlink -f "$library")"
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libfreetype.so.6]' <<< "$dynamic" ||
    die 'FreeType SONAME is wrong.'
for needed in libz.so.1 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "FreeType is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'FreeType contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'FreeType contains an absolute build path.'
fi

package="$root/build/system-packages/freetype-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name freetype --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'zlib>=1.3.2' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'FREETYPE_PACKAGE_READY: %s\n' "$package"
