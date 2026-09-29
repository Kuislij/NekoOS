#!/usr/bin/env bash
# Build PCRE2 runtime libraries and development files against NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/pcre2/build.sh'

version=10.48
archive=pcre2-$version.tar.gz
url=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$version/$archive
# Upstream release attestation: https://github.com/PCRE2Project/pcre2/attestations/44153304
sha256=ebcc25aadf2a51fa1fefa9b8bc9e7a79b3dae86870a0f1152a22e42befd46888
sha512=7682828c8bf512406f3f1bff773830416e55750bec1cf4bb39a1238f5a61026df71817dbd2dd0fcd72a76fcfb15d7b386a64739b33ad99bad77170652248fa35

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar make python3 readelf strip strings find readlink; do
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

work="$root/build/system-package-build/pcre2-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/pcre2-$version"
stage="$work/stage"

(
    cd "$work/build"
    CC="$root/scripts/host-musl-gcc.sh" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --enable-shared --disable-static \
        --enable-pcre2-8 --enable-pcre2-16 --enable-pcre2-32 \
        --enable-unicode --enable-jit \
        --disable-pcre2grep-libz --disable-pcre2grep-libbz2 \
        --disable-pcre2test-libedit --disable-pcre2test-libreadline
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

# The match/test utilities are build products, not runtime requirements of GLib.
rm -f -- "$stage/usr/bin/pcre2grep" "$stage/usr/bin/pcre2test"
find "$stage/usr/lib" -type f -name '*.la' -delete
rm -rf -- "$stage/usr/share/man" "$stage/usr/share/doc" "$stage/usr/share/info"
install -Dm 644 "$src/LICENCE.md" "$stage/usr/share/licenses/pcre2/LICENCE.md"
install -Dm 644 "$src/deps/sljit/LICENSE" "$stage/usr/share/licenses/pcre2/sljit-LICENSE"

for width in 8 16 32; do
    soname="libpcre2-$width.so.0"
    library="$stage/usr/lib/$soname"
    [[ -L "$library" && -L "$stage/usr/lib/libpcre2-$width.so" &&
       -f "$stage/usr/lib/pkgconfig/libpcre2-$width.pc" ]] ||
        die "PCRE2 $width-bit runtime or development files are missing."
    library="$(readlink -f "$library")"
    strip --strip-unneeded "$library"
    dynamic="$(readelf -d "$library")"
    grep -Fq "Library soname: [$soname]" <<< "$dynamic" ||
        die "PCRE2 $width-bit SONAME is wrong."
    grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
        die "PCRE2 $width-bit library is not linked against NekoOS musl."
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "PCRE2 $width-bit library contains a host runtime dependency or build path."
    fi
    if strings "$library" | grep -F "$root/" >/dev/null; then
        die "PCRE2 $width-bit library contains an absolute build path."
    fi
    grep -Fq "Version: $version" "$stage/usr/lib/pkgconfig/libpcre2-$width.pc" ||
        die "PCRE2 $width-bit pkg-config version is wrong."
done

library="$stage/usr/lib/libpcre2-posix.so.3"
[[ -L "$library" && -L "$stage/usr/lib/libpcre2-posix.so" &&
   -f "$stage/usr/lib/pkgconfig/libpcre2-posix.pc" &&
   -f "$stage/usr/include/pcre2.h" &&
   -f "$stage/usr/include/pcre2posix.h" &&
   -x "$stage/usr/bin/pcre2-config" ]] ||
    die 'PCRE2 POSIX runtime or development files are missing.'
library="$(readlink -f "$library")"
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libpcre2-posix.so.3]' <<< "$dynamic" ||
    die 'PCRE2 POSIX SONAME is wrong.'
grep -Fq 'Shared library: [libpcre2-8.so.0]' <<< "$dynamic" ||
    die 'PCRE2 POSIX does not link to the 8-bit library.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'PCRE2 POSIX is not linked against NekoOS musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'PCRE2 POSIX contains a host runtime dependency or build path.'
fi
grep -Fq "Version: $version" "$stage/usr/lib/pkgconfig/libpcre2-posix.pc" ||
    die 'PCRE2 POSIX pkg-config version is wrong.'

package="$root/build/system-packages/pcre2-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name pcre2 --version "$version" --arch x86_64 \
    --license BSD-3-Clause --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'PCRE2_PACKAGE_READY: %s\n' "$package"
