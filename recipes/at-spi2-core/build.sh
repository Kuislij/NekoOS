#!/usr/bin/env bash
# Build ATK, the ATK bridge, and AT-SPI for the NekoOS musl desktop.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/at-spi2-core/build.sh'

version=2.58.9
archive=at-spi2-core-$version.tar.xz
url=https://download.gnome.org/sources/at-spi2-core/2.58/$archive
sha256=c8eacbe2640038178f2c2cd7abef2c23c7a4777909119f9d815c7151b39fb82a
sha512=1cea287fc78a350353f65b7232623a0c58d5009a0bbed38157865cae479fb712f8e983704e6f34e3c384a28b51afd735550a5045fe4b475fd388d0407d690f47
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
for tool in curl sha256sum sha512sum tar python3 ninja ar strip readelf strings find; do
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
glib_source="$root/cache/sources/glib-$glib_version.tar.xz"
[[ -f "$glib_source" ]] || die 'Build packaged GLib first.'
printf '%s  %s\n' "$glib_sha256" "$glib_source" | sha256sum -c -

prerequisites=(libffi-3.5.2.nspkg pcre2-10.48.nspkg zlib-1.3.2.nspkg
    glib-2.84.4.nspkg expat-2.8.5.nspkg dbus-1.16.2.nspkg
    xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg libxext-1.3.7.nspkg libxfixes-6.0.2.nspkg
    libxi-1.8.3.nspkg libxtst-1.2.5.nspkg)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/at-spi2-core-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" "$work/host-tools" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/at-spi2-core-$version"

# Upstream libxml2 is used only by the test XML loader. Keep all accessibility
# runtime components; skip cross-built test executables and optional Python GI
# overrides, since introspection is disabled. Fail if the pinned source changes.
python3 - "$src/meson.build" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
data = path.read_text()
changes = {
    "libxml_dep = dependency('libxml-2.0', version: libxml_req_version)":
        "# NekoOS: libxml2 is only used by the excluded upstream tests.",
    "  subdir('tests')": "  # NekoOS: guest test binaries are excluded.",
    "  if python.found()": "  if python.found() and have_gir",
}
for before, after in changes.items():
    if data.count(before) != 1:
        raise SystemExit(f'AT-SPI no-tests adjustment no longer matches: {before}')
    data = data.replace(before, after)
path.write_text(data)
PY

# These pure Python host generators come from the verified GLib source, never
# from host GLib or a mutable work directory belonging to another recipe.
for generator in glib-genmarshal glib-mkenums; do
    tar -xOf "$glib_source" "glib-$glib_version/gobject/$generator.in" |
        sed "s|@PYTHON@|/usr/bin/env python3|; s|@VERSION@|$glib_version|" \
        > "$work/host-tools/$generator"
    chmod 755 "$work/host-tools/$generator"
done
cat > "$work/native.ini" <<EOF
[binaries]
glib-genmarshal = '$work/host-tools/glib-genmarshal'
glib-mkenums = '$work/host-tools/glib-mkenums'
EOF
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
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
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    export PATH="$work/host-tools:$PATH"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --native-file "$work/native.ini" \
        --prefix=/usr --libdir=lib --libexecdir=libexec --sysconfdir=/etc \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dintrospection=disabled -Ddocs=false -Duse_systemd=false \
        -Dgtk2_atk_adaptor=false -Dx11=enabled -Ddbus_daemon=/usr/bin/dbus-daemon
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)

install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/at-spi2-core/COPYING"
for component in atk-1.0 atk-bridge-2.0 atspi; do
    library="$stage/usr/lib/lib$component.so.0"
    [[ -L "$library" && -L "$stage/usr/lib/lib$component.so" ]] ||
        die "Accessibility shared library is missing: $component"
    grep -Fq "Library soname: [lib$component.so.0]" < <(readelf -d "$library") ||
        die "Accessibility library has a wrong SONAME: $component"
done
for pc in atk atk-bridge-2.0 atspi-2; do
    [[ -f "$stage/usr/lib/pkgconfig/$pc.pc" ]] || die "Missing $pc metadata."
done
[[ -f "$stage/usr/include/atk-1.0/atk/atk.h" &&
   -f "$stage/usr/include/at-spi2-atk/2.0/atk-bridge.h" &&
   -f "$stage/usr/include/at-spi-2.0/atspi/atspi.h" &&
   -f "$stage/usr/libexec/at-spi-bus-launcher" &&
   -f "$stage/usr/libexec/at-spi2-registryd" &&
   -f "$stage/usr/share/dbus-1/services/org.a11y.Bus.service" &&
   -f "$stage/usr/share/defaults/at-spi2/accessibility.conf" ]] ||
    die 'Accessibility development files, services, or daemons are missing.'

while IFS= read -r -d '' binary; do
    [[ "$(readelf -h "$binary" 2>/dev/null | sed -n 's/.*Class:[[:space:]]*//p' | head -1)" == ELF64 ]] || continue
    strip --strip-unneeded "$binary"
    dynamic="$(readelf -d "$binary")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "Accessibility binary contains a host dependency or build path: $binary"
    fi
    if strings "$binary" | grep -F "$root/" >/dev/null; then
        die "Accessibility binary contains an absolute build path: $binary"
    fi
done < <(find "$stage/usr" -type f -print0)
for binary in "$stage/usr/libexec/at-spi-bus-launcher" "$stage/usr/libexec/at-spi2-registryd"; do
    readelf -l "$binary" |
        grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' ||
        die "Accessibility daemon lacks the NekoOS musl loader: $binary"
done

package="$root/build/system-packages/at-spi2-core-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name at-spi2-core --version "$version" --arch x86_64 \
    --license LGPL-2.1-or-later --source-sha256 "$sha256" \
    --depends 'glib>=2.84.4' --depends 'dbus>=1.16.2' \
    --depends 'libx11>=1.8.13' --depends 'libxi>=1.8.3' --depends 'libxtst>=1.2.5' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
python3 "$root/tools/system_package.py" install "$package" --root "$sysroot" >/dev/null
(
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    "$root/scripts/host-musl-gcc.sh" -O2 \
        -ffile-prefix-map="$root"=/usr/src/nekoos \
        $("$pkgconf" --cflags atk atk-bridge-2.0 atspi-2) \
        "$root/recipes/at-spi2-core/smoke.c" \
        -Wl,-rpath-link,"$sysroot/usr/lib" \
        $("$pkgconf" --libs atk atk-bridge-2.0 atspi-2 gobject-2.0) \
        -o "$work/atspi-smoke"
)
readelf -l "$work/atspi-smoke" |
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' ||
    die 'AT-SPI smoke executable does not use the NekoOS musl loader.'
"$root/build/toolchain-root/usr/lib/libc.so" \
    --library-path "$sysroot/usr/lib" "$work/atspi-smoke"
printf 'ATSPI_PACKAGE_READY: %s\n' "$package"
