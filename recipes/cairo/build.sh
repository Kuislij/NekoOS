#!/usr/bin/env bash
# Build the Cairo image, text and X11 drawing backends for the NekoOS desktop.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/cairo/build.sh'

version=1.18.6
archive=cairo-$version.tar.xz
url=https://cairographics.org/releases/$archive
# Published at https://cairographics.org/news/cairo-1.18.6/.
sha256=1c767308174337a74694da0f3ec069c271452163a1ef4540964c50c301f157d4

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$meson" && "$(python3 "$meson" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/pixman/build.sh).'
for tool in curl sha256sum tar python3 ninja ar strip readelf strings find; do
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

# Include transitive packages so pkg-config can resolve private development
# dependencies without consulting the Linux build host.
prerequisites=(
    expat-2.8.5.nspkg
    fontconfig-2.17.1.nspkg
    freetype-2.14.3.nspkg
    glib-2.84.4.nspkg
    libffi-3.5.2.nspkg
    libpng-1.6.58.nspkg
    libx11-1.8.13.nspkg
    libxau-1.0.12.nspkg
    libxcb-1.17.0.nspkg
    libxdmcp-1.1.5.nspkg
    libxext-1.3.7.nspkg
    libxrender-0.9.12.nspkg
    pcre2-10.48.nspkg
    pixman-0.46.4.nspkg
    xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    zlib-1.3.2.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/cairo-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
for pc in fontconfig freetype2 glib-2.0 gobject-2.0 libpng pixman-1 \
          x11 xcb xcb-render xext xrender; do
    [[ -f "$sysroot/usr/lib/pkgconfig/$pc.pc" ]] ||
        die "Packaged Cairo prerequisite is missing $pc.pc"
done

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/cairo-$version"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'

[properties]
needs_exe_wrapper = true
ipc_rmid_deferred_release = false

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

(
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dauto_features=disabled -Dtests=disabled -Dgtk_doc=false \
        -Dpng=enabled -Dfreetype=enabled -Dfontconfig=enabled \
        -Dxlib=enabled -Dxcb=enabled -Dglib=enabled -Dzlib=enabled \
        -Dtee=disabled -Dxlib-xcb=disabled -Dlzo=disabled \
        -Dgtk2-utils=disabled -Dsymbol-lookup=disabled -Dspectre=disabled
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)

install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/cairo/COPYING"
install -Dm 644 "$src/COPYING-LGPL-2.1" \
    "$stage/usr/share/licenses/cairo/COPYING-LGPL-2.1"
install -Dm 644 "$src/COPYING-MPL-1.1" \
    "$stage/usr/share/licenses/cairo/COPYING-MPL-1.1"

library="$(readlink -f "$stage/usr/lib/libcairo.so.2")"
gobject_library="$(readlink -f "$stage/usr/lib/libcairo-gobject.so.2")"
[[ -f "$library" && -f "$gobject_library" &&
   -L "$stage/usr/lib/libcairo.so" &&
   -L "$stage/usr/lib/libcairo-gobject.so" &&
   -f "$stage/usr/include/cairo/cairo.h" &&
   -f "$stage/usr/include/cairo/cairo-ft.h" &&
   -f "$stage/usr/include/cairo/cairo-xlib.h" &&
   -f "$stage/usr/include/cairo/cairo-xlib-xrender.h" &&
   -f "$stage/usr/include/cairo/cairo-xcb.h" &&
   -f "$stage/usr/include/cairo/cairo-pdf.h" &&
   -f "$stage/usr/include/cairo/cairo-ps.h" &&
   -f "$stage/usr/include/cairo/cairo-svg.h" &&
   -f "$stage/usr/lib/pkgconfig/cairo.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-png.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-ft.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-xlib.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-xlib-xrender.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-xcb.pc" &&
   -f "$stage/usr/lib/pkgconfig/cairo-gobject.pc" ]] ||
    die 'Cairo shared libraries, headers or pkg-config files are missing.'

for elf in "$library" "$gobject_library"; do
    strip --strip-unneeded "$elf"
    dynamic="$(readelf -d "$elf")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
       strings "$elf" | grep -F "$root/" >/dev/null; then
        die "Cairo contains a host runtime dependency or build path: $elf"
    fi
done
grep -Fq 'Library soname: [libcairo.so.2]' < <(readelf -d "$library") ||
    die 'Cairo SONAME is wrong.'
grep -Fq 'Library soname: [libcairo-gobject.so.2]' \
    < <(readelf -d "$gobject_library") ||
    die 'Cairo-GObject SONAME is wrong.'
for needed in libpixman-1.so.0 libpng16.so.16 libfreetype.so.6 \
              libfontconfig.so.1 libX11.so.6 libXrender.so.1 libxcb.so.1 libc.so; do
    grep -Fq "Shared library: [$needed]" < <(readelf -d "$library") ||
        die "Cairo is missing runtime dependency $needed."
done

(
    export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    read -r -a cairo_cflags <<< "$("$pkgconf" --cflags cairo-gobject)"
    read -r -a cairo_libs <<< "$("$pkgconf" --libs cairo-gobject)"
    "$root/scripts/host-musl-gcc.sh" \
        "${cairo_cflags[@]}" -I"$stage/usr/include/cairo" \
        -L"$stage/usr/lib" -Wl,-rpath-link,"$sysroot/usr/lib" \
        "$root/recipes/cairo/smoke.c" "${cairo_libs[@]}" \
        -o "$work/cairo-smoke"
)
"$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$stage/usr/lib:$sysroot/usr/lib" \
    "$work/cairo-smoke" "$work/smoke.png" ||
    die 'Cairo runtime image/PNG drawing failed.'
[[ -s "$work/smoke.png" ]] || die 'Cairo produced an empty PNG.'

package="$root/build/system-packages/cairo-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name cairo --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'fontconfig>=2.17.1' --depends 'freetype>=2.14.3' \
    --depends 'glib>=2.84.4' --depends 'libpng>=1.6.58' \
    --depends 'libx11>=1.8.13' --depends 'libxcb>=1.17.0' \
    --depends 'libxext>=1.3.7' --depends 'libxrender>=0.9.12' \
    --depends 'pixman>=0.46.4' --depends 'zlib>=1.3.2' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'CAIRO_PACKAGE_READY: %s\n' "$package"
