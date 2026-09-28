#!/usr/bin/env bash
# Build the DRM/KMS userspace library needed by Xorg's modesetting driver.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libdrm/build.sh'

version=2.4.134
archive=libdrm-$version.tar.xz
url=https://dri.freedesktop.org/libdrm/$archive
sha256=ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95
sha512=ef2abddea59d1e93c83a48de920431b839ab50d6071ef4da3cf126e7d64ba7b235f2e34e1169d49ad9de2937a0a18acd66bb8d324b067239b1136e0ddbe792a1

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$meson" && "$(python3 "$meson" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/pixman/build.sh).'
for tool in curl sha256sum sha512sum tar ninja python3 readelf strip strings; do
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

work="$root/build/system-package-build/libdrm-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libdrm-$version"
stage="$work/stage"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

# The generic KMS API suffices for QEMU's virtio GPU. Per-vendor APIs and
# host probing libraries are intentionally out of scope for this package.
python3 "$meson" setup "$work/build" "$src" \
    --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
    --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled \
    -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled \
    -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled \
    -Dvc4=disabled -Detnaviv=disabled -Dcairo-tests=disabled \
    -Dman-pages=disabled -Dvalgrind=disabled -Dudev=false -Dtests=false \
    -Dinstall-test-programs=false
python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild

# Upstream has no top-level COPYING file. Keep the exact notices from the
# build definition and the core DRM implementation in the package.
mkdir -p "$stage/usr/share/licenses/libdrm"
sed -n '1,18p' "$src/meson.build" > "$stage/usr/share/licenses/libdrm/meson-notice.txt"
sed -n '9,32p' "$src/xf86drm.c" > "$stage/usr/share/licenses/libdrm/core-notice.txt"

library="$stage/usr/lib/libdrm.so.2.134.0"
[[ -f "$library" && -L "$stage/usr/lib/libdrm.so.2" &&
   -L "$stage/usr/lib/libdrm.so" && -f "$stage/usr/include/xf86drm.h" &&
   -f "$stage/usr/include/xf86drmMode.h" &&
   -f "$stage/usr/include/libdrm/drm_mode.h" &&
   -f "$stage/usr/lib/pkgconfig/libdrm.pc" ]] ||
    die 'libdrm runtime or development files are missing.'
strip --strip-unneeded "$library"
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libdrm.so.2]' <<< "$dynamic" ||
    die 'libdrm SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'libdrm is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'libdrm contains a host runtime dependency or build path.'
fi
if strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libdrm contains an absolute build path.'
fi

package="$root/build/system-packages/libdrm-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libdrm --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBDRM_PACKAGE_READY: %s\n' "$package"
