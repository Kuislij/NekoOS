#!/usr/bin/env bash
# Build the foreign-function interface used by GObject against NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libffi/build.sh'

version=3.5.2
archive=libffi-$version.tar.gz
url=https://github.com/libffi/libffi/releases/download/v$version/$archive
sha256=f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc
sha512=76974a84e3aee6bbd646a6da2e641825ae0b791ca6efdc479b2d4cbcd3ad607df59cffcf5031ad5bd30822961a8c6de164ac8ae379d1804acd388b1975cdbf4d

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar make readelf strip strings find; do
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

work="$root/build/system-package-build/libffi-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libffi-$version"
stage="$work/stage"

(
    cd "$work/build"
    CC="$root/scripts/host-musl-gcc.sh" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --enable-shared --disable-static
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

install -Dm 644 "$src/LICENSE" "$stage/usr/share/licenses/libffi/LICENSE"
rm -f -- "$stage/usr/lib/libffi.la"
rm -rf -- "$stage/usr/share/man" "$stage/usr/share/info"

library="$stage/usr/lib/libffi.so.8"
[[ -L "$library" && -L "$stage/usr/lib/libffi.so" &&
   -f "$stage/usr/lib/pkgconfig/libffi.pc" &&
   -n "$(find "$stage/usr" -type f -name ffi.h -print -quit)" &&
   -n "$(find "$stage/usr" -type f -name ffitarget.h -print -quit)" ]] ||
    die 'libffi shared library or development files are missing.'
library="$(readlink -f "$library")"
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libffi.so.8]' <<< "$dynamic" ||
    die 'libffi SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'libffi is not linked against NekoOS musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libffi contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libffi contains an absolute build path.'
fi

package="$root/build/system-packages/libffi-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libffi --version "$version" --arch x86_64 \
    --license MIT --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBFFI_PACKAGE_READY: %s\n' "$package"
