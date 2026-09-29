#!/usr/bin/env bash
# Build the XML parser used by fontconfig and D-Bus against NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/expat/build.sh'

version=2.8.5
archive=expat-$version.tar.xz
url=https://github.com/libexpat/libexpat/releases/download/R_2_8_5/$archive
# Published as the release asset digest by the upstream GitHub Releases API.
sha256=1e727b8933ec51a77a9a9d9afcf8e688bce45d907c13e36ab7393fe36e703182
sha512=ad3d4198a70682c7c8b2149cb7c743585cc9470ea2e4bd81ec7c0aff9545d9010b51df5cfcd0714335c7ef1578537cbd2a5580f649246b4ea78ee5e3466808a3

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

work="$root/build/system-package-build/expat-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/expat-$version"
stage="$work/stage"

(
    cd "$work/build"
    CC="$root/scripts/host-musl-gcc.sh" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --enable-shared --disable-static \
        --without-xmlwf --without-examples --without-tests --without-docbook
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

find "$stage/usr/lib" -type f -name '*.la' -delete
rm -rf -- "$stage/usr/share/man" "$stage/usr/share/doc" "$stage/usr/share/info"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/expat/COPYING"

library="$stage/usr/lib/libexpat.so.1"
[[ -L "$library" && -L "$stage/usr/lib/libexpat.so" &&
   -f "$stage/usr/include/expat.h" &&
   -f "$stage/usr/include/expat_config.h" &&
   -f "$stage/usr/include/expat_external.h" &&
   -f "$stage/usr/lib/pkgconfig/expat.pc" ]] ||
    die 'Expat shared library or development files are missing.'
library="$(readlink -f "$library")"
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libexpat.so.1]' <<< "$dynamic" ||
    die 'Expat SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'Expat is not linked against NekoOS musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'Expat contains a host runtime dependency or build path.'
fi
grep -Fq "Version: $version" "$stage/usr/lib/pkgconfig/expat.pc" ||
    die 'Expat pkg-config version is wrong.'

"$root/scripts/host-musl-gcc.sh" \
    -I"$stage/usr/include" -L"$stage/usr/lib" \
    "$root/recipes/expat/smoke.c" -lexpat -o "$work/expat-smoke"
"$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$stage/usr/lib" "$work/expat-smoke" ||
    die 'Expat runtime XML parse failed.'

package="$root/build/system-packages/expat-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name expat --version "$version" --arch x86_64 \
    --license MIT --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'EXPAT_PACKAGE_READY: %s\n' "$package"
