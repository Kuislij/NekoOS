#!/usr/bin/env bash
# Build a small SHA-1 provider for the NekoOS X.Org server against musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libsha1/build.sh'

version=0.3
# Official upstream tag 0.3 resolves to this commit, so the source archive is
# addressed by immutable commit rather than GitHub's movable branch name.
commit=3f976bbb57d77f0c6964ecd5fbd3d99a2b9f65e5
archive=libsha1-$version-$commit.tar.gz
url=https://codeload.github.com/dottedmag/libsha1/tar.gz/$commit
sha256=0ef7b0ead391ce5d1c99ab1d68bbc5128e18a60bfd1d245f9d760753889bec67
sha512=9b982e83c2d4db9e0f66f4320fca4daf3be50d2eddb01df18880b6e8d27ec9d65dd7f7971784409a562c50e1d24f79edda1556cc5bfd17af80ad64564bb3098f

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar readelf strings strip; do
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

work="$root/build/system-package-build/libsha1-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage/usr/lib/pkgconfig" \
    "$work/stage/usr/include" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libsha1-$commit"
stage="$work/stage"
compiler="$root/scripts/host-musl-gcc.sh"

# Upstream's tag provides Autotools input, not a generated configure script.
# Its Makefile.am builds precisely sha1.c as libsha1 and installs libsha1.h.
# x86_64 NekoOS is little-endian; make that choice explicit for this source.
"$compiler" -std=c99 -O2 -fPIC -ffile-prefix-map="$root=/usr/src/nekoos" \
    -DPLATFORM_BYTE_ORDER=1234 -DIS_LITTLE_ENDIAN=1234 \
    -c "$src/sha1.c" -o "$work/sha1.o"
"$compiler" -shared -Wl,-soname,libsha1.so.0 \
    -o "$stage/usr/lib/libsha1.so.0.0.0" "$work/sha1.o"
strip --strip-unneeded "$stage/usr/lib/libsha1.so.0.0.0"
ln -s libsha1.so.0.0.0 "$stage/usr/lib/libsha1.so.0"
ln -s libsha1.so.0 "$stage/usr/lib/libsha1.so"
install -m 644 "$src/libsha1.h" "$stage/usr/include/libsha1.h"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libsha1/COPYING"
cat > "$stage/usr/lib/pkgconfig/libsha1.pc" <<EOF
prefix=/usr
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libsha1
Description: Tiny SHA1 implementation for embedded devices.
Version: $version
Cflags: -I\${includedir}
Libs: -L\${libdir} -lsha1
EOF

library="$stage/usr/lib/libsha1.so.0.0.0"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libsha1.so.0]' <<< "$dynamic" ||
    die 'libsha1 SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'libsha1 is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libsha1 contains a host runtime dependency or build path.'
fi

# Exercise the staged shared library using a standard FIPS SHA-1 test vector.
cat > "$work/probe.c" <<'EOF'
#include <stdio.h>
#include "libsha1.h"

int main(void) {
    unsigned char digest[SHA1_DIGEST_SIZE];
    sha1(digest, (const unsigned char *)"abc", 3);
    for (unsigned i = 0; i < SHA1_DIGEST_SIZE; ++i)
        printf("%02x", digest[i]);
    putchar('\n');
    return 0;
}
EOF
"$compiler" -std=c99 -O2 -I"$stage/usr/include" "$work/probe.c" \
    -L"$stage/usr/lib" -lsha1 -o "$work/probe"
digest="$("$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$stage/usr/lib" "$work/probe")"
[[ "$digest" == a9993e364706816aba3e25717850c26c9cd0d89d ]] ||
    die "libsha1 test vector failed: $digest"

package="$root/build/system-packages/libsha1-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libsha1 --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBSHA1_PACKAGE_READY: %s\n' "$package"
