#!/usr/bin/env bash
# Build the pinned compression library used by X.Org font libraries.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/zlib/build.sh'

version=1.3.2
archive=zlib-$version.tar.xz
url=https://zlib.net/$archive
# Published at https://zlib.net/.
sha256=d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum tar make python3 readelf strip strings ar ranlib nm; do
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

work="$root/build/system-package-build/zlib-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/zlib-$version"
stage="$work/stage"
(
    cd "$src"
    CC="$root/scripts/host-musl-gcc.sh" \
    AR="$(command -v ar)" RANLIB="$(command -v ranlib)" NM="$(command -v nm)" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    ./configure --prefix=/usr --libdir=/usr/lib
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
rm -f -- "$stage/usr/lib/libz.a"
rm -rf -- "$stage/usr/share/man"
install -Dm 644 "$src/LICENSE" "$stage/usr/share/licenses/zlib/LICENSE"

library="$stage/usr/lib/libz.so.1.3.2"
[[ -f "$library" && -L "$stage/usr/lib/libz.so.1" &&
   -L "$stage/usr/lib/libz.so" && -f "$stage/usr/include/zlib.h" &&
   -f "$stage/usr/include/zconf.h" &&
   -f "$stage/usr/lib/pkgconfig/zlib.pc" ]] ||
    die 'zlib runtime or development files are missing.'
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libz.so.1]' <<< "$dynamic" ||
    die 'zlib SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'zlib is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'zlib contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'zlib contains an absolute build path.'
fi

package="$root/build/system-packages/zlib-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name zlib --version "$version" --arch x86_64 \
    --license Zlib --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'ZLIB_PACKAGE_READY: %s\n' "$package"
