#!/usr/bin/env bash
# Build Pango's Unicode layout and Cairo/FreeType text rendering backends.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/pango/build.sh'
version=1.56.4
archive=pango-$version.tar.xz
url=https://download.gnome.org/sources/pango/1.56/$archive
# Published at https://download.gnome.org/sources/pango/1.56/pango-1.56.4.sha256sum.
sha256=17065e2fcc5f5a5bdbffc884c956bfc7c451a96e8c4fb2f8ad837c6413cb5a01
glib_sha256=8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90
[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 && -f "$meson" &&
   "$(python3 "$meson" --version)" == 1.10.1 ]] || die 'Build the pinned host pkgconf and Meson first.'
for tool in curl sha256sum tar python3 ninja gcc ar strip readelf strings nm find; do
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
glib_source="$root/cache/sources/glib-2.84.4.tar.xz"
[[ -f "$glib_source" ]] || die 'Build GLib first to cache its pinned host generator sources.'
printf '%s  %s\n' "$glib_sha256" "$glib_source" | sha256sum -c -
prerequisites=(
    cairo-1.18.6.nspkg dejavu-fonts-2.37.nspkg expat-2.8.5.nspkg
    fontconfig-2.17.1.nspkg freetype-2.14.3.nspkg fribidi-1.0.16.nspkg
    glib-2.84.4.nspkg harfbuzz-12.3.0.nspkg libffi-3.5.2.nspkg libpng-1.6.58.nspkg
    libx11-1.8.13.nspkg libxau-1.0.12.nspkg libxcb-1.17.0.nspkg
    libxdmcp-1.1.5.nspkg libxext-1.3.7.nspkg libxrender-0.9.12.nspkg
    pcre2-10.48.nspkg pixman-0.46.4.nspkg xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg zlib-1.3.2.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done
work="$root/build/system-package-build/pango-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] || die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" "$work/host-tools" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" --root "$sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/pango-$version"
tar -xOf "$glib_source" glib-2.84.4/gobject/glib-mkenums.in |
    sed "s|@PYTHON@|$(command -v python3)|g; s|@VERSION@|2.84.4|g" > "$work/host-tools/glib-mkenums"
chmod +x "$work/host-tools/glib-mkenums"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
# Pango declares C++ for its Windows backend. The Linux backend uses C only;
# GCC accepts the Meson .cpp sanity check without a C++ standard runtime.
cpp = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'

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
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dauto_features=disabled -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled \
        -Dlibthai=disabled -Dxft=disabled -Dsysprof=disabled -Dintrospection=disabled \
        -Ddocumentation=false -Dman-pages=false -Dbuild-testsuite=false -Dbuild-examples=false
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/pango/COPYING"
for component in pango pangoft2 pangocairo; do
    library="$(readlink -f "$stage/usr/lib/lib$component-1.0.so.0")"
    [[ -f "$library" && -L "$stage/usr/lib/lib$component-1.0.so" &&
       -f "$stage/usr/lib/pkgconfig/$component.pc" ]] || die "Pango component $component is missing."
    grep -Fq "Library soname: [lib$component-1.0.so.0]" < <(readelf -d "$library") || die 'Pango SONAME is wrong.'
done
[[ -f "$stage/usr/include/pango-1.0/pango/pango.h" &&
   -f "$stage/usr/include/pango-1.0/pango/pangocairo.h" && -f "$stage/usr/bin/pango-view" ]] ||
    die 'Pango development headers or renderer utility are missing.'
while IFS= read -r -d '' binary; do
    readelf -h "$binary" >/dev/null 2>&1 || continue
    strip --strip-unneeded "$binary"
    dynamic="$(readelf -d "$binary")"
    grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die "Pango ELF is not linked against musl: $binary"
    if grep -Eq '\((RPATH|RUNPATH)\)|Shared library: \[(libc.so.6|libstdc\+\+|libgcc_s)' <<< "$dynamic" ||
       nm -D --undefined-only "$binary" | grep -vE ' w __cxa_finalize$' |
           grep -Eq '__cxa|_Unwind|[[:space:]]_Z|GLIBC_' ||
       strings "$binary" | grep -F "$root/" >/dev/null; then
        die "Pango contains a host runtime dependency or build path: $binary"
    fi
    if [[ "$binary" == "$stage/usr/bin/"* ]]; then
        grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' < <(readelf -l "$binary") ||
            die "Pango utility lacks the NekoOS musl interpreter: $binary"
    fi
done < <(find "$stage/usr" -type f -print0)
(
    export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    cflags_text="$("$pkgconf" --cflags pangocairo fontconfig)"
    libs_text="$("$pkgconf" --libs pangocairo fontconfig)"
    read -r -a flags <<< "$cflags_text"
    read -r -a libs <<< "$libs_text"
    "$root/scripts/host-musl-gcc.sh" "${flags[@]}" -I"$stage/usr/include/pango-1.0" \
        -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib:$sysroot/usr/lib" \
        "$root/recipes/pango/smoke.c" "${libs[@]}" -o "$work/pango-smoke"
)
FONTCONFIG_FILE="$sysroot/usr/etc/fonts/fonts.conf" FONTCONFIG_PATH="$sysroot/usr/etc/fonts" \
    FONTCONFIG_SYSROOT="$sysroot" \
    "$root/build/toolchain-root/usr/lib/libc.so" --library-path "$stage/usr/lib:$sysroot/usr/lib" \
    "$work/pango-smoke" "$work/smoke.png"
[[ -s "$work/smoke.png" ]] || die 'Pango produced an empty PNG.'
package="$root/build/system-packages/pango-$version.nspkg"
python3 "$root/tools/system_package.py" build --root "$stage" --name pango \
    --version "$version" --arch x86_64 --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'cairo>=1.18.6' --depends 'fontconfig>=2.17.1' --depends 'freetype>=2.14.3' \
    --depends 'fribidi>=1.0.16' --depends 'glib>=2.84.4' --depends 'harfbuzz>=12.3.0' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'PANGO_PACKAGE_READY: %s\n' "$package"
