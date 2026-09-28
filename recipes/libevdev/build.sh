#!/usr/bin/env bash
# Build libevdev for NekoOS musl without host-distribution libraries.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libevdev/build.sh'

version=1.13.7
archive=libevdev-$version.tar.xz
url=https://www.freedesktop.org/software/libevdev/$archive
sha256=0caf824971108f15bb2ad356433bae198d7d3bf1e82d43f63626e069e060bfa6
sha512=fd64ded32a7f303d45d545ebf293cc9d1a1e79672e1d5879d05e2c723b78709d1ecc972afb1f043eafe961cbded06d221a6fccc25ebba00a68fcf76e4ee3da8b

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$meson" && "$(python3 "$meson" --version)" == 1.10.1 ]] ||
    die 'Build the pinned Meson host tool first (bash recipes/xorgproto/build.sh).'
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

work="$root/build/system-package-build/libevdev-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/empty-pkgconfig" \
    "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libevdev-$version"
stage="$work/stage"

cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '/bin/false'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

PKG_CONFIG_LIBDIR="$work/empty-pkgconfig" \
CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
python3 "$meson" setup "$work/build" "$src" \
    --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
    --buildtype=release --wrap-mode=nofallback \
    -Dtests=disabled -Dtools=disabled -Ddocumentation=disabled
python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild

rm -rf -- "$stage/usr/share/man"
strip --strip-unneeded "$stage/usr/lib/libevdev.so.2.3.0"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libevdev/COPYING"

library="$stage/usr/lib/libevdev.so.2.3.0"
[[ -f "$library" && -L "$stage/usr/lib/libevdev.so" &&
   -L "$stage/usr/lib/libevdev.so.2" &&
   -f "$stage/usr/include/libevdev-1.0/libevdev/libevdev.h" &&
   -f "$stage/usr/include/libevdev-1.0/libevdev/libevdev-uinput.h" &&
   -f "$stage/usr/lib/pkgconfig/libevdev.pc" ]] ||
    die 'libevdev runtime or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libevdev.so.2]' <<< "$dynamic" ||
    die 'libevdev SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'libevdev is not linked against NekoOS musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libevdev contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libevdev contains an absolute build path.'
fi

package="$root/build/system-packages/libevdev-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libevdev --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBEVDEV_PACKAGE_READY: %s\n' "$package"
