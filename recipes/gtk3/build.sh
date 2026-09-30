#!/usr/bin/env bash
# Build GTK 3 for the NekoOS X11 session from the pinned upstream release.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/gtk3/build.sh'
version=3.24.52
archive=gtk-$version.tar.xz
url=https://download.gnome.org/sources/gtk/3.24/$archive
sha256=80931fa472a77b9a164f6740e3c0b444fac6770054632d35a7ff9d679e5e7b9f
glib_version=2.84.4
glib_sha256=8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$root/build/host-musl-gcc.specs" && -x "$pkgconf" && -f "$meson" ]] ||
    die 'Build the pinned musl toolchain and host tools first (bash os build).'
for tool in curl sha256sum tar python3 ninja ar strip readelf strings find msgfmt; do
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
glib_source="$root/cache/sources/glib-$glib_version.tar.xz"
[[ -f "$glib_source" ]] || die 'Build the pinned GLib package first.'
printf '%s  %s\n' "$glib_sha256" "$glib_source" | sha256sum -c -
prerequisites=(
    pixman-0.46.4.nspkg xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg
    zlib-1.3.2.nspkg libpng-1.6.58.nspkg libffi-3.5.2.nspkg
    expat-2.8.5.nspkg freetype-2.14.3.nspkg fontconfig-2.17.1.nspkg
    dbus-1.16.2.nspkg pcre2-10.48.nspkg glib-2.84.4.nspkg
    libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg libxext-1.3.7.nspkg libxrender-0.9.12.nspkg
    libxfixes-6.0.2.nspkg libxrandr-1.5.5.nspkg cairo-1.18.6.nspkg
    libxi-1.8.3.nspkg libxcursor-1.2.3.nspkg libxinerama-1.1.6.nspkg
    libxcomposite-0.4.7.nspkg libxdamage-1.1.7.nspkg libxtst-1.2.5.nspkg
    at-spi2-core-2.58.9.nspkg libepoxy-1.5.10.nspkg
    harfbuzz-12.3.0.nspkg fribidi-1.0.16.nspkg pango-1.56.4.nspkg
    gdk-pixbuf-2.44.8.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done
work="$root/build/system-package-build/gtk3-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" "$work/host-tools" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" --root "$sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
tar --no-same-owner -xf "$glib_source" -C "$work/sources" \
    "glib-$glib_version/gobject/glib-genmarshal.in" \
    "glib-$glib_version/gobject/glib-mkenums.in" \
    "glib-$glib_version/gio/gdbus-2.0/codegen"
src="$work/sources/gtk-$version"
glib_src="$work/sources/glib-$glib_version"
for generator in glib-genmarshal glib-mkenums; do
    sed -e 's|@PYTHON@|/usr/bin/env python3|g' -e "s|@VERSION@|$glib_version|g" \
        "$glib_src/gobject/$generator.in" > "$work/host-tools/$generator"
    chmod 755 "$work/host-tools/$generator"
done
codegen="$glib_src/gio/gdbus-2.0/codegen"
sed -e "s|@VERSION@|$glib_version|g" -e 's|@MAJOR_VERSION@|2|g' \
    -e 's|@MINOR_VERSION@|84|g' "$codegen/config.py.in" > "$codegen/config.py"
sed -e 's|@PYTHON@|/usr/bin/env python3|g' \
    "$codegen/gdbus-codegen.in" > "$codegen/gdbus-codegen"
cat > "$work/host-tools/gdbus-codegen" <<EOF
#!/bin/sh
export UNINSTALLED_GLIB_SRCDIR='$glib_src'
exec python3 '$codegen/gdbus-codegen' "\$@"
EOF
for tool in glib-compile-resources glib-compile-schemas gdk-pixbuf-pixdata; do
    cat > "$work/host-tools/$tool" <<EOF
#!/bin/sh
exec '$root/build/toolchain-root/usr/lib/libc.so' --library-path '$sysroot/usr/lib' '$sysroot/usr/bin/$tool' "\$@"
EOF
done
chmod 755 "$work"/host-tools/*
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'
glib-genmarshal = '$work/host-tools/glib-genmarshal'
glib-mkenums = '$work/host-tools/glib-mkenums'
gdbus-codegen = '$work/host-tools/gdbus-codegen'
glib-compile-resources = '$work/host-tools/glib-compile-resources'
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
    export GDK_PIXBUF_PIXDATA="$work/host-tools/gdk-pixbuf-pixdata"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    # Resolve compiler flags in the sysroot, but keep runtime directory
    # variables such as X11_DATA_PREFIX at the guest's canonical /usr.
    export PKG_CONFIG_FDO_SYSROOT_RULES=1
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib --sysconfdir=/etc \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dx11_backend=true -Dwayland_backend=false -Dbroadway_backend=false \
        -Dwin32_backend=false -Dquartz_backend=false -Dxinerama=yes \
        -Dcloudproviders=false -Dprofiler=false -Dtracker3=false \
        -Dprint_backends=file -Dcolord=no -Dgtk_doc=false -Dman=false \
        -Dintrospection=false -Ddemos=false -Dexamples=false \
        -Dtests=false -Dinstalled_tests=false -Dbuiltin_immodules=all
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)
# Meson deliberately skips target post-install tools when cross compiling.
"$root/build/toolchain-root/usr/lib/libc.so" --library-path "$sysroot/usr/lib" \
    "$sysroot/usr/bin/glib-compile-schemas" "$stage/usr/share/glib-2.0/schemas"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/gtk3/COPYING"
for component in gtk gdk; do
    library="$(readlink -f "$stage/usr/lib/lib$component-3.so.0")"
    [[ -f "$library" && -L "$stage/usr/lib/lib$component-3.so" ]] || die "GTK component $component is missing."
    grep -Fq "Library soname: [lib$component-3.so.0]" < <(readelf -d "$library") || die "Wrong $component SONAME."
done
[[ -f "$stage/usr/include/gtk-3.0/gtk/gtk.h" &&
   -f "$stage/usr/lib/pkgconfig/gtk+-3.0.pc" &&
   -f "$stage/usr/lib/pkgconfig/gtk+-x11-3.0.pc" &&
   -f "$stage/usr/share/glib-2.0/schemas/gschemas.compiled" ]] || die 'GTK headers, metadata or compiled settings are missing.'
while IFS= read -r -d '' elf; do
    [[ "$(readelf -h "$elf" 2>/dev/null | sed -n 's/.*Class:[[:space:]]*//p' | head -1)" == ELF64 ]] || continue
    strip --strip-unneeded "$elf"
    dynamic="$(readelf -d "$elf")"
    if grep -Eq '\((RPATH|RUNPATH)\)|libc.so.6' <<< "$dynamic" ||
       strings "$elf" | grep -F "$root/" >/dev/null; then
        die "GTK contains a host dependency or build path: $elf"
    fi
done < <(find "$stage/usr" -type f -print0)
for binary in "$stage"/usr/bin/*; do
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
        < <(readelf -l "$binary") || die "GTK utility lacks the musl interpreter: $binary"
done
"$root/build/toolchain-root/usr/lib/libc.so" --library-path "$stage/usr/lib:$sysroot/usr/lib" \
    "$stage/usr/bin/gtk-query-immodules-3.0" > "$work/immodules.txt"
package="$root/build/system-packages/gtk3-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name gtk3 --version "$version" --arch x86_64 \
    --license LGPL-2.1-or-later --source-sha256 "$sha256" \
    --depends 'at-spi2-core>=2.58.9' --depends 'cairo>=1.18.6' \
    --depends 'fontconfig>=2.17.1' --depends 'fribidi>=1.0.16' \
    --depends 'gdk-pixbuf>=2.44.8' --depends 'glib>=2.84.4' \
    --depends 'harfbuzz>=12.3.0' --depends 'libepoxy>=1.5.10' \
    --depends 'libx11>=1.8.13' --depends 'libxcomposite>=0.4.7' \
    --depends 'libxcursor>=1.2.3' --depends 'libxdamage>=1.1.7' \
    --depends 'libxext>=1.3.7' --depends 'libxfixes>=6.0.2' \
    --depends 'libxi>=1.8.3' --depends 'libxinerama>=1.1.6' \
    --depends 'libxrandr>=1.5.5' --depends 'libxrender>=0.9.12' \
    --depends 'pango>=1.56.4' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'GTK3_PACKAGE_READY: %s\n' "$package"
