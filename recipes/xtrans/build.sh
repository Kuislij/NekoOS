#!/usr/bin/env bash
# Package X.Org's shared X11 transport sources for the NekoOS musl build.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xtrans/build.sh'

version=1.6.0
archive=xtrans-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg-announce@lists.x.org/msg01797.html
sha256=faafea166bf2451a173d9d593352940ec6404145c5d1da5c213423ce4d359e92
sha512=e0ac4a2df0eeacdf23cedd74fee063a8eea81d05c4c4c9a9a113b9b4238db7cacb3c831973ac647fe1a5b06426dcdf0b2f8be5ac27862700333269880e25725b

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar make python3; do
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

work="$root/build/system-package-build/xtrans-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/xtrans-$version"
stage="$work/stage"

# xtrans is source that gets compiled into consumers (not a shared library).
# Configure with the target compiler so xtrans.pc exports musl-compatible flags.
(
    cd "$work/build"
    PKG_CONFIG=/bin/false CC="$root/scripts/host-musl-gcc.sh" \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --disable-docs
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/xtrans/COPYING"

[[ -f "$stage/usr/include/X11/Xtrans/Xtrans.h" &&
   -f "$stage/usr/include/X11/Xtrans/Xtrans.c" &&
   -f "$stage/usr/include/X11/Xtrans/Xtransint.h" &&
   -f "$stage/usr/include/X11/Xtrans/Xtranssock.c" &&
   -f "$stage/usr/include/X11/Xtrans/transport.c" &&
   -f "$stage/usr/share/pkgconfig/xtrans.pc" &&
   -f "$stage/usr/share/aclocal/xtrans.m4" &&
   -f "$stage/usr/share/licenses/xtrans/COPYING" ]] ||
    die 'Expected xtrans development files are missing.'
grep -Fq 'Version: 1.6.0' "$stage/usr/share/pkgconfig/xtrans.pc" ||
    die 'xtrans pkg-config version is wrong.'

package="$root/build/system-packages/xtrans-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xtrans --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'XTRANS_PACKAGE_READY: %s\n' "$package"
