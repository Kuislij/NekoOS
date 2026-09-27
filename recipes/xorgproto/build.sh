#!/usr/bin/env bash
# Build X.Org protocol headers and pkg-config metadata for the NekoOS X11 stack.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xorgproto/build.sh'

xorgproto_version=2025.1
xorgproto_url=https://xorg.freedesktop.org/releases/individual/proto/xorgproto-2025.1.tar.xz
# Published in the X.Org xorg-announce release message on 2025-12-19.
xorgproto_sha256=56898c716c0578df8a2d828c9c3e5c528277705c0484381a81960fe1a67668e8
xorgproto_sha512=dbbee3aa1bc62721d64309e1d98807d403609d8129944b2e23e48f95d30c6448718c2842362994d67647908645bafc757c710070c5dcdca96d191fd2689d023a

meson_version=1.10.1
meson_url=https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz
meson_sha256=c42296f12db316a4515b9375a5df330f2e751ccdd4f608430d41d7d6210e4317

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar python3 ninja ar strip; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

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
fetch "$xorgproto_url" "$xorgproto_sha256"
printf '%s  %s\n' "$xorgproto_sha512" \
    "$root/cache/sources/xorgproto-$xorgproto_version.tar.xz" | sha512sum -c -

host_tools="$root/build/host-tools"
meson_source="$host_tools/meson-$meson_version"
[[ ! -L "$host_tools" && ! -L "$meson_source" ]] ||
    die 'Host tools must not be symlinks.'
mkdir -p "$host_tools"
if [[ ! -f "$meson_source/.neko-extracted" ]]; then
    rm -rf -- "$meson_source"
    tar --no-same-owner -xf "$root/cache/sources/meson-$meson_version.tar.gz" -C "$host_tools"
    touch "$meson_source/.neko-extracted"
fi
meson=(python3 "$meson_source/meson.py")
[[ "$("${meson[@]}" --version)" == "$meson_version" ]] || die 'Wrong Meson version.'

work="$root/build/system-package-build/xorgproto-$xorgproto_version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$root/cache/sources/xorgproto-$xorgproto_version.tar.xz" \
    -C "$work/sources"
source_dir="$work/sources/xorgproto-$xorgproto_version"
build_dir="$work/build"
stage="$work/stage"

# Although xorgproto is header-only, configure for the same target compiler as
# subsequent X11 libraries so generated headers reflect the NekoOS ABI.
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

"${meson[@]}" setup "$build_dir" "$source_dir" \
    --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
    --buildtype=release --wrap-mode=nofallback -Dlegacy=false
"${meson[@]}" compile -C "$build_dir" -j "${JOBS:-4}"
DESTDIR="$stage" "${meson[@]}" install -C "$build_dir" --no-rebuild

# Upstream has distinct notices for the bundled protocols, including GL.
mkdir -p "$stage/usr/share/licenses/xorgproto"
for notice in "$source_dir"/COPYING-*; do
    [[ -f "$notice" ]] || die 'Upstream license notices are missing.'
    install -m 644 "$notice" "$stage/usr/share/licenses/xorgproto/"
done

[[ -f "$stage/usr/include/X11/X.h" &&
   -f "$stage/usr/include/X11/extensions/XI2proto.h" &&
   -f "$stage/usr/include/GL/glxproto.h" &&
   -f "$stage/usr/share/pkgconfig/xproto.pc" &&
   -f "$stage/usr/share/pkgconfig/inputproto.pc" &&
   -f "$stage/usr/share/licenses/xorgproto/COPYING-glproto" ]] ||
    die 'Expected X.Org protocol development files are missing.'

package="$root/build/system-packages/xorgproto-$xorgproto_version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xorgproto --version "$xorgproto_version" \
    --arch x86_64 --license MIT --source-sha256 "$xorgproto_sha256" \
    --output "$package"
printf 'XORGPROTO_PACKAGE_READY: %s\n' "$package"
