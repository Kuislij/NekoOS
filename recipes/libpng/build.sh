#!/usr/bin/env bash
# Build the PNG image library against packaged zlib and NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libpng/build.sh'

version=1.6.58
archive=libpng-$version.tar.xz
url=https://download.sourceforge.net/libpng/$archive
# Published by the PNG Group at https://www.libpng.org/pub/png/libpng.html.
sha256=28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum tar make python3 readelf strip strings find readlink; do
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

zlib="$root/build/system-packages/zlib-1.3.2.nspkg"
[[ -f "$zlib" ]] || die "Missing prerequisite system package: $zlib"
python3 "$root/tools/system_package.py" verify "$zlib" >/dev/null

work="$root/build/system-package-build/libpng-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
stage="$work/stage"
sysroot="$work/sysroot"
python3 "$root/tools/system_package.py" install "$zlib" --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/include/zlib.h" && -f "$sysroot/usr/lib/libz.so.1" ]] ||
    die 'Packaged zlib development files are incomplete.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libpng-$version"
(
    cd "$work/build"
    CC="$root/scripts/host-musl-gcc.sh" \
    CPPFLAGS="-I$sysroot/usr/include" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    LDFLAGS="-L$sysroot/usr/lib -Wl,-rpath-link,$sysroot/usr/lib" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -name '*.la' -delete
rm -rf -- "$stage/usr/share/man" "$stage/usr/share/doc" "$stage/usr/share/info"
install -Dm 644 "$src/LICENSE" "$stage/usr/share/licenses/libpng/LICENSE"

library="$stage/usr/lib/libpng16.so.16"
[[ -L "$library" && -L "$stage/usr/lib/libpng16.so" &&
   -f "$stage/usr/include/png.h" && -f "$stage/usr/include/pngconf.h" &&
   -f "$stage/usr/include/pnglibconf.h" &&
   -f "$stage/usr/lib/pkgconfig/libpng16.pc" ]] ||
    die 'libpng shared library or development files are missing.'
library="$(readlink -f "$library")"
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libpng16.so.16]' <<< "$dynamic" ||
    die 'libpng SONAME is wrong.'
for needed in libz.so.1 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libpng is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libpng contains a host runtime dependency or build path.'
fi
for utility in pngfix png-fix-itxt; do
    binary="$stage/usr/bin/$utility"
    [[ -f "$binary" ]] || die "Missing libpng utility: $utility"
    readelf -l "$binary" |
        grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' ||
        die "$utility uses the wrong runtime loader."
    utility_dynamic="$(readelf -d "$binary")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$utility_dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$utility_dynamic" ||
       strings "$binary" | grep -F "$root/" >/dev/null; then
        die "$utility contains a host runtime dependency or build path."
    fi
    strip --strip-unneeded "$binary"
done
grep -Fq "Version: $version" "$stage/usr/lib/pkgconfig/libpng16.pc" ||
    die 'libpng pkg-config version is wrong.'

"$root/scripts/host-musl-gcc.sh" \
    -I"$stage/usr/include" -L"$stage/usr/lib" -L"$sysroot/usr/lib" \
    -Wl,-rpath-link,"$sysroot/usr/lib" \
    "$root/recipes/libpng/smoke.c" -lpng16 -lz -o "$work/libpng-smoke"
"$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$stage/usr/lib:$sysroot/usr/lib" "$work/libpng-smoke" ||
    die 'libpng runtime PNG encode/decode failed.'

package="$root/build/system-packages/libpng-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libpng --version "$version" --arch x86_64 \
    --license libpng-2.0 --source-sha256 "$sha256" \
    --depends 'zlib>=1.3.2' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBPNG_PACKAGE_READY: %s\n' "$package"
