#!/usr/bin/env bash
# Build the first reusable Xorg/Cairo graphics library against NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/pixman/build.sh'

pixman_version=0.46.4
pixman_url=https://cairographics.org/releases/pixman-0.46.4.tar.gz
pixman_sha256=d09c44ebc3bd5bee7021c79f922fe8fb2fb57f7320f55e97ff9914d2346a591c
# Published by upstream at pixman-0.46.4.tar.gz.sha512.
pixman_sha512=10ddb88b51f5456c440d77a7b4230600b099e818378a9b55f715bbe5ec3d9f1e9da2124d28a2bd3377f1ab20af87e0ec4fa9dadaa20a2f1f880dd2dc7f27ca6c
meson_version=1.10.1
meson_url=https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz
meson_sha256=c42296f12db316a4515b9375a5df330f2e751ccdd4f608430d41d7d6210e4317

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
command -v ninja >/dev/null || die 'Ninja is required on the Linux build host.'
command -v python3 >/dev/null || die 'Python 3 is required on the Linux build host.'
command -v gcc >/dev/null || die 'GCC is required on the Linux build host.'

fetch() {
    local url="$1" hash="$2" archive
    archive="$root/cache/sources/${url##*/}"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            -o "$archive.part" "$url"
        printf '%s  %s\n' "$hash" "$archive.part" | sha256sum -c -
        mv -- "$archive.part" "$archive"
    fi
    printf '%s  %s\n' "$hash" "$archive" | sha256sum -c -
}

fetch "$meson_url" "$meson_sha256"
fetch "$pixman_url" "$pixman_sha256"
printf '%s  %s\n' "$pixman_sha512" "$root/cache/sources/pixman-$pixman_version.tar.gz" |
    sha512sum -c -

host_tools="$root/build/host-tools"
meson_source="$host_tools/meson-$meson_version"
[[ ! -L "$host_tools" && ! -L "$meson_source" ]] || die 'Host tools must not be symlinks.'
mkdir -p "$host_tools"
if [[ ! -f "$meson_source/.neko-extracted" ]]; then
    rm -rf -- "$meson_source"
    tar --no-same-owner -xf "$root/cache/sources/meson-$meson_version.tar.gz" -C "$host_tools"
    touch "$meson_source/.neko-extracted"
fi
meson=(python3 "$meson_source/meson.py")
[[ "$("${meson[@]}" --version)" == "$meson_version" ]] || die 'Wrong Meson version.'

work="$root/build/system-package-build/pixman-$pixman_version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$root/cache/sources/pixman-$pixman_version.tar.gz" -C "$work/sources"
source_dir="$work/sources/pixman-$pixman_version"
build_dir="$work/build"
stage="$work/stage"
compiler="$root/scripts/host-musl-gcc.sh"
archive_tool="$(command -v ar)"
strip_tool="$(command -v strip)"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$compiler'
ar = '$archive_tool'
strip = '$strip_tool'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

"${meson[@]}" setup "$build_dir" "$source_dir" \
    --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
    --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
    -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled \
    -Dopenmp=disabled
"${meson[@]}" compile -C "$build_dir" -j "${JOBS:-4}"
DESTDIR="$stage" "${meson[@]}" install -C "$build_dir" --no-rebuild
install -Dm 644 "$source_dir/COPYING" "$stage/usr/share/licenses/pixman/COPYING"

library="$stage/usr/lib/libpixman-1.so.0.46.4"
[[ -f "$library" ]] || die 'Pixman shared library was not staged.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
    die 'Pixman is not linked against musl.'
grep -Fq 'Library soname: [libpixman-1.so.0]' <<< "$dynamic" ||
    die 'Pixman SONAME is wrong.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic"; then
    die 'Pixman must not contain a build-path runtime search path.'
fi
[[ "$(readlink "$stage/usr/lib/libpixman-1.so.0")" == 'libpixman-1.so.0.46.4' &&
   "$(readlink "$stage/usr/lib/libpixman-1.so")" == 'libpixman-1.so.0' ]] ||
    die 'Pixman shared-library symlink chain is broken.'
[[ -f "$stage/usr/include/pixman-1/pixman.h" &&
   -f "$stage/usr/lib/pkgconfig/pixman-1.pc" ]] || die 'Pixman development files are missing.'

package="$root/build/system-packages/pixman-$pixman_version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name pixman --version "$pixman_version" --arch x86_64 \
    --license MIT --source-sha256 "$pixman_sha256" --output "$package"
printf 'PIXMAN_PACKAGE_READY: %s\n' "$package"
