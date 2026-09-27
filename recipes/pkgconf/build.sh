#!/usr/bin/env bash
# Keep host pkg-config metadata resolution independent of the host distro.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/pkgconf/build.sh'

version=2.5.1
url=https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz
sha256=cd05c9589b9f86ecf044c10a2269822bc9eb001eced2582cfffd658b0a50c243
archive="$root/cache/sources/pkgconf-$version.tar.xz"

if [[ ! -f "$archive" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        -o "$archive.part" "$url"
    printf '%s  %s\n' "$sha256" "$archive.part" | sha256sum -c -
    mv -- "$archive.part" "$archive"
fi
printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c -

work="$root/build/host-tools/pkgconf-$version"
[[ ! -L "$root/build/host-tools" && ! -L "$work" ]] ||
    die 'Host pkgconf work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build"
tar --no-same-owner -xf "$archive" -C "$work/sources"
source_dir="$work/sources/pkgconf-$version"
(
    cd "$work/build"
    "$source_dir/configure" --prefix="$work/install" --disable-shared
)
make -C "$work/build" -j "${JOBS:-4}"
make -C "$work/build" install
[[ "$("$work/install/bin/pkgconf" --version)" == "$version" ]] ||
    die 'Wrong host pkgconf version.'
printf 'HOST_PKGCONF_READY: %s\n' "$work/install/bin/pkgconf"
