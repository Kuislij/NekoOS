#!/usr/bin/env bash
# Build the PNG/XPM image-loading layer for NekoOS GTK applications.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/gdk-pixbuf/build.sh'

version=2.44.8
archive=gdk-pixbuf-$version.tar.xz
url=https://download.gnome.org/sources/gdk-pixbuf/2.44/$archive
# Published in the adjacent GNOME release .sha256sum file.
sha256=919f529512961a12e81cd4b4b466a48c3933469e7f9a310c6513cd4fb252ba3c
glib_version=2.84.4
glib_sha256=8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90

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
glib_source_file="$root/cache/sources/glib-$glib_version.tar.xz"
[[ -f "$glib_source_file" ]] || die 'Build the pinned GLib package first.'
printf '%s  %s\n' "$glib_sha256" "$glib_source_file" | sha256sum -c -

prerequisites=(
    glib-2.84.4.nspkg
    libffi-3.5.2.nspkg
    libpng-1.6.58.nspkg
    pcre2-10.48.nspkg
    zlib-1.3.2.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/gdk-pixbuf-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" \
    "$work/host-tools" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
for pc in glib-2.0 gio-2.0 gobject-2.0 gmodule-no-export-2.0 libpng; do
    [[ -f "$sysroot/usr/lib/pkgconfig/$pc.pc" ]] ||
        die "Packaged GdkPixbuf prerequisite is missing $pc.pc"
done

tar --no-same-owner -xf "$source_file" -C "$work/sources"
tar --no-same-owner -xf "$glib_source_file" -C "$work/sources" \
    "glib-$glib_version/gobject/glib-genmarshal.in" \
    "glib-$glib_version/gobject/glib-mkenums.in"
src="$work/sources/gdk-pixbuf-$version"
# These generators are Python scripts from the same pinned GLib sources as
# the target libraries. Never select an unrelated Ubuntu generator from PATH.
for generator in glib-genmarshal glib-mkenums; do
    sed -e 's|@PYTHON@|/usr/bin/env python3|g' \
        -e "s|@VERSION@|$glib_version|g" \
        "$work/sources/glib-$glib_version/gobject/$generator.in" \
        > "$work/host-tools/$generator"
    chmod 755 "$work/host-tools/$generator"
done
# GdkPixbuf checks for this utility even with resource-based tests disabled.
# Run the packaged target binary through our musl loader on the x86_64 host.
cat > "$work/host-tools/glib-compile-resources" <<EOF
#!/bin/sh
exec '$root/build/toolchain-root/usr/lib/libc.so' --library-path '$sysroot/usr/lib' '$sysroot/usr/bin/glib-compile-resources' "\$@"
EOF
chmod 755 "$work/host-tools/glib-compile-resources"

cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'
glib-genmarshal = '$work/host-tools/glib-genmarshal'
glib-mkenums = '$work/host-tools/glib-mkenums'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

(
    export PATH="$work/host-tools:$PATH"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dauto_features=disabled -Dpng=enabled -Dlegacy_xpm=enabled \
        -Dbuiltin_loaders=png,xpm -Djpeg=disabled -Dtiff=disabled \
        -Dgif=disabled -Dothers=disabled -Dglycin=disabled -Dandroid=disabled \
        -Dtests=false -Dinstalled_tests=false -Dintrospection=disabled \
        -Ddocumentation=false -Dman=false -Dthumbnailer=disabled \
        -Dgio_sniffing=false -Drelocatable=false
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)

install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/gdk-pixbuf/COPYING"
# PNG and XPM are built into the shared library. Keep the advertised module
# cache valid and deterministic without running a host query-loaders binary.
cache_file="$stage/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
mkdir -p "$(dirname -- "$cache_file")"
printf '%s\n' '# NekoOS: PNG and XPM loaders are built into libgdk_pixbuf-2.0.' > "$cache_file"

library="$(readlink -f "$stage/usr/lib/libgdk_pixbuf-2.0.so.0")"
[[ -f "$library" && -L "$stage/usr/lib/libgdk_pixbuf-2.0.so" &&
   -f "$stage/usr/include/gdk-pixbuf-2.0/gdk-pixbuf/gdk-pixbuf.h" &&
   -f "$stage/usr/lib/pkgconfig/gdk-pixbuf-2.0.pc" &&
   -f "$stage/usr/bin/gdk-pixbuf-csource" &&
   -f "$stage/usr/bin/gdk-pixbuf-pixdata" &&
   -f "$stage/usr/bin/gdk-pixbuf-query-loaders" ]] ||
    die 'GdkPixbuf runtime, headers, metadata or image utilities are missing.'
[[ -z "$(find "$stage/usr/lib" -name 'libpixbufloader-*.so' -print -quit)" ]] ||
    die 'Unexpected dynamic GdkPixbuf loader; the builtin-only cache would be incomplete.'

while IFS= read -r -d '' elf; do
    [[ "$(readelf -h "$elf" 2>/dev/null | sed -n 's/.*Class:[[:space:]]*//p' | head -1)" == ELF64 ]] || continue
    strip --strip-unneeded "$elf"
    dynamic="$(readelf -d "$elf")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
       strings "$elf" | grep -F "$root/" >/dev/null; then
        die "GdkPixbuf contains a host runtime dependency or build path: $elf"
    fi
done < <(find "$stage/usr" -type f -print0)
grep -Fq 'Library soname: [libgdk_pixbuf-2.0.so.0]' < <(readelf -d "$library") ||
    die 'GdkPixbuf SONAME is wrong.'
for needed in libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 \
              libgmodule-2.0.so.0 libpng16.so.16 libc.so; do
    grep -Fq "Shared library: [$needed]" < <(readelf -d "$library") ||
        die "GdkPixbuf is missing runtime dependency $needed."
done
for binary in "$stage"/usr/bin/*; do
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
        < <(readelf -l "$binary") ||
        die "GdkPixbuf utility lacks the NekoOS musl interpreter: $binary"
done

(
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    read -r -a smoke_cflags <<< "$("$pkgconf" --cflags gio-2.0 gobject-2.0)"
    read -r -a smoke_libs <<< "$("$pkgconf" --libs gio-2.0 gobject-2.0)"
    "$root/scripts/host-musl-gcc.sh" \
        "${smoke_cflags[@]}" -I"$stage/usr/include/gdk-pixbuf-2.0" \
        -L"$stage/usr/lib" -Wl,-rpath-link,"$sysroot/usr/lib" \
        "$root/tests/gdk_pixbuf_runtime.c" -lgdk_pixbuf-2.0 "${smoke_libs[@]}" \
        -o "$work/gdk-pixbuf-smoke"
)
GDK_PIXBUF_MODULE_FILE=/nonexistent-neko-gdk-pixbuf-cache \
    "$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$stage/usr/lib:$sysroot/usr/lib" \
    "$work/gdk-pixbuf-smoke" "$work/smoke.png" ||
    die 'GdkPixbuf PNG round trip, incremental decoding, scaling or XPM loading failed.'

package="$root/build/system-packages/gdk-pixbuf-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name gdk-pixbuf --version "$version" --arch x86_64 \
    --license LGPL-2.1-or-later --source-sha256 "$sha256" \
    --depends 'glib>=2.84.4' --depends 'libpng>=1.6.58' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'GDK_PIXBUF_PACKAGE_READY: %s\n' "$package"
