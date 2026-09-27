#!/usr/bin/env bash
# Cross-build upstream XCB against the NekoOS musl/X11 system packages.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxcb/build.sh'

version=1.17.0
archive=libxcb-$version.tar.xz
url=https://xcb.freedesktop.org/dist/$archive
# X.Org release announcement: https://lists.x.org/archives/xorg-announce/2024-April/003507.html
sha256=599ebf9996710fea71622e6e184f3a8ad5b43d0e5fa8c4e407123c88a59a6d55
sha512=945b1f28e8b407a4d0ebf88c99ef3cbef763fd75e6eaa8e971946e44ce8dbe9b478c56ae85aaaadab7fdb25987e88570d9d4fb9ad2febd6d6bf21d644a0e10d0

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
host_proto="$root/build/host-tools/xcb-proto-1.17.0/stage/usr"
xml_dir="$host_proto/share/xcb"
python_dir="$(find "$host_proto/lib" -type d -name xcbgen -print -quit 2>/dev/null)"
python_dir="${python_dir%/xcbgen}"
[[ -f "$host_proto/share/pkgconfig/xcb-proto.pc" &&
   -f "$xml_dir/xproto.xml" &&
   -f "$python_dir/xcbgen/__init__.py" ]] ||
    die 'Build host xcb-proto first (bash recipes/xcb-proto/build.sh).'
PYTHONPATH="$python_dir" python3 -c 'import xcbgen; import xcbgen.error'

for tool in curl sha256sum sha512sum tar make python3 readelf; do
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

proto="$root/build/system-packages/xorgproto-2025.1.nspkg"
xau="$root/build/system-packages/libxau-1.0.12.nspkg"
xdmcp="$root/build/system-packages/libxdmcp-1.1.5.nspkg"
for package in "$proto" "$xau" "$xdmcp"; do
    [[ -f "$package" ]] || die "Missing prerequisite system package: $package"
    python3 "$root/tools/system_package.py" verify "$package" >/dev/null
done

work="$root/build/system-package-build/libxcb-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "$proto" "$xau" "$xdmcp" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/include/X11/X.h" &&
   -f "$sysroot/usr/include/X11/Xauth.h" &&
   -f "$sysroot/usr/include/X11/Xdmcp.h" &&
   -f "$sysroot/usr/lib/libXau.so.6.0.0" &&
   -f "$sysroot/usr/lib/libXdmcp.so.6.0.0" ]] ||
    die 'Prerequisite packages did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/libxcb-$version"

# xcb-proto is build-host data. Its .pc file deliberately points at its own
# staging prefix; pkgconf's target sysroot must not be prepended to the XML and
# Python generator paths. This small wrapper corrects only those two queries.
cat > "$work/pkg-config" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if (( $# == 2 )) && [[ "$2" == xcb-proto ]]; then
    case "$1" in
        --variable=xcbincludedir) printf '%s\n' "$XCBPROTO_XML_DIR"; exit 0 ;;
        --variable=pythondir) printf '%s\n' "$XCBPROTO_PYTHON_DIR"; exit 0 ;;
    esac
fi
exec "$NEKO_PKGCONF" "$@"
EOF
chmod 755 "$work/pkg-config"

(
    cd "$work/build"
    export NEKO_PKGCONF="$pkgconf" XCBPROTO_XML_DIR="$xml_dir" \
        XCBPROTO_PYTHON_DIR="$python_dir"
    export PKG_CONFIG="$work/pkg-config"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig:$host_proto/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export PYTHONPATH="$python_dir"
    unset PKG_CONFIG_PATH
    CPPFLAGS="-I$sysroot/usr/include" \
    LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib" \
    CC="$root/scripts/host-musl-gcc.sh" PYTHON=python3 \
    "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
        --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
        --enable-shared --disable-static --disable-devel-docs --without-doxygen \
        --disable-selinux --disable-xevie --disable-xprint
    make -j "${JOBS:-4}"
    make DESTDIR="$stage" install
)

# Libtool archives contain host staging paths and are never needed by NekoOS.
find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/libxcb/COPYING"

library="$stage/usr/lib/libxcb.so.1.1.0"
[[ -f "$library" && -L "$stage/usr/lib/libxcb.so" &&
   -L "$stage/usr/lib/libxcb.so.1" &&
   -f "$stage/usr/include/xcb/xcb.h" &&
   -f "$stage/usr/lib/pkgconfig/xcb.pc" ]] ||
    die 'libxcb core library or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libxcb.so.1]' <<< "$dynamic" ||
    die 'libxcb SONAME is wrong.'
for needed in libc.so libXau.so.6 libXdmcp.so.6; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "libxcb is missing expected runtime dependency $needed."
done
while IFS= read -r -d '' shared; do
    dynamic="$(readelf -d "$shared")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic"; then
        die "libxcb library contains a build-path runtime search path: $shared"
    fi
    if grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "libxcb library is linked against host glibc: $shared"
    fi
done < <(find "$stage/usr/lib" -maxdepth 1 -type f -name 'libxcb*.so.*' -print0)

package="$root/build/system-packages/libxcb-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxcb --version "$version" --arch x86_64 \
    --license MIT --source-sha256 "$sha256" \
    --depends 'libxau>=1.0.12' --depends 'libxdmcp>=1.1.5' \
    --depends 'xorgproto>=2025.1' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXCB_PACKAGE_READY: %s\n' "$package"
