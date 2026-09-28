#!/usr/bin/env bash
# Build the multi-touch event translation library for NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/mtdev/build.sh'

version=1.1.7
archive=mtdev-$version.tar.bz2
url=https://bitmath.se/org/code/mtdev/$archive
# Official release: https://bitmath.se/org/code/mtdev/
sha256=a107adad2101fecac54ac7f9f0e0a0dd155d954193da55c2340c97f2ff1d814e
sha512=e6174a38cf67a7f12a3b91e4e27bf74a18d6b40a956950ebb748b0ff87092333daa07e647b26038a5a533f8c48e845d649848e6ba99ea009ab87fd96ed188152

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar make python3 readelf strip strings; do
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

work="$root/build/system-package-build/mtdev-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" \
    "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/mtdev-$version"
stage="$work/stage"
(
    cd "$work/build"
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    CC="$root/scripts/host-musl-gcc.sh" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib \
        --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/mtdev/COPYING"

library="$stage/usr/lib/libmtdev.so.1.0.0"
[[ -f "$library" && -L "$stage/usr/lib/libmtdev.so.1" &&
   -L "$stage/usr/lib/libmtdev.so" &&
   -f "$stage/usr/include/mtdev.h" &&
   -f "$stage/usr/lib/pkgconfig/mtdev.pc" &&
   -f "$stage/usr/bin/mtdev-test" ]] ||
    die 'mtdev runtime, test utility, or development files are missing.'
strip --strip-unneeded "$library" "$stage/usr/bin/mtdev-test"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libmtdev.so.1]' <<< "$dynamic" ||
    die 'mtdev SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'mtdev is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'mtdev contains a host runtime dependency or build path.'
fi
test_dynamic="$(readelf -d "$stage/usr/bin/mtdev-test")"
grep -Fq 'Shared library: [libmtdev.so.1]' <<< "$test_dynamic" ||
    die 'mtdev-test does not use the packaged shared library.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$test_dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$test_dynamic"; then
    die 'mtdev-test contains a host runtime dependency or build path.'
fi
readelf -l "$stage/usr/bin/mtdev-test" | grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'mtdev-test does not use the NekoOS musl interpreter.'

package="$root/build/system-packages/mtdev-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name mtdev --version "$version" --arch x86_64 \
    --license MIT --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'MTDEV_PACKAGE_READY: %s\n' "$package"
