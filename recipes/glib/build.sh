#!/usr/bin/env bash
# Cross-build the GLib, GObject, and GIO foundations for NekoOS musl.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/glib/build.sh'

version=2.84.4
archive=glib-$version.tar.xz
url=https://download.gnome.org/sources/glib/2.84/$archive
# GNOME publishes this digest alongside the release archive.
sha256=8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90
sha512=2de9b2f7376c0e5f6ee585087090675d597c474199a10d04aad18df688b6ca77d17e93a86ec07482898663f51c82121992272496318138f77ca5ad2c340a4bd3

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

prerequisites=(
    libffi-3.5.2.nspkg
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

work="$root/build/system-package-build/glib-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/libffi.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/libpcre2-8.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/zlib.pc" ]] ||
    die 'GLib prerequisite development files are missing.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/glib-$version"
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
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dtests=false -Dinstalled_tests=false -Dintrospection=disabled \
        -Ddocumentation=false -Dman-pages=disabled -Dnls=disabled \
        -Dlibmount=disabled -Dselinux=disabled -Dlibelf=disabled \
        -Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)

install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/glib/COPYING"
cp -a -- "$src/LICENSES" "$stage/usr/share/licenses/glib/"

# NekoOS does not yet ship Python or the Autotools stack. These installed
# generators are only useful on a build host, while the guest ELF tools below
# work with the shipped musl runtime. Keep pkg-config from advertising absent
# generator paths.
for generator in gdbus-codegen glib-genmarshal glib-mkenums \
                 gtester-report glib-gettextize; do
    [[ -f "$stage/usr/bin/$generator" ]] ||
        die "Expected host-only GLib generator is missing: $generator"
    rm -f -- "$stage/usr/bin/$generator"
done
rm -rf -- "$stage/usr/share/glib-2.0/codegen" \
    "$stage/usr/share/glib-2.0/gdb" "$stage/usr/share/gdb" \
    "$stage/usr/share/bash-completion" "$stage/usr/share/glib-2.0/valgrind"
sed -i '/^glib_genmarshal=/d; /^glib_mkenums=/d' \
    "$stage/usr/lib/pkgconfig/glib-2.0.pc"
sed -i '/^gdbus_codegen=/d' "$stage/usr/lib/pkgconfig/gio-2.0.pc"

for name in glib gobject gio; do
    [[ -L "$stage/usr/lib/lib$name-2.0.so" &&
       -L "$stage/usr/lib/lib$name-2.0.so.0" &&
       -f "$stage/usr/lib/pkgconfig/$name-2.0.pc" ]] ||
        die "GLib component $name is missing its library or pkg-config file."
done
[[ -f "$stage/usr/include/glib-2.0/glib.h" &&
   -f "$stage/usr/include/glib-2.0/glib-object.h" &&
   -f "$stage/usr/include/glib-2.0/gio/gio.h" &&
   -f "$stage/usr/lib/glib-2.0/include/glibconfig.h" &&
   -f "$stage/usr/lib/pkgconfig/gio-unix-2.0.pc" &&
   -f "$stage/usr/bin/gio" &&
   -f "$stage/usr/bin/glib-compile-schemas" ]] ||
    die 'GLib development headers, GIO metadata or utilities are missing.'

for binary in "$stage"/usr/bin/* "$stage"/usr/libexec/*; do
    [[ -f "$binary" ]] || continue
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
        < <(readelf -l "$binary") ||
        die "GLib utility lacks the NekoOS musl interpreter: $binary"
done

# All guest ELF files must use the musl ABI without host runtime paths.
while IFS= read -r -d '' binary; do
    [[ "$(readelf -h "$binary" 2>/dev/null | sed -n 's/.*Class:[[:space:]]*//p' | head -1)" == ELF64 ]] || continue
    strip --strip-unneeded "$binary"
    dynamic="$(readelf -d "$binary")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "GLib contains a host dependency or build path: $binary"
    fi
    if strings "$binary" | grep -F "$root/" >/dev/null; then
        die "GLib contains an absolute build path: $binary"
    fi
done < <(find "$stage/usr" -type f -print0)

glib_library="$(readlink -f "$stage/usr/lib/libglib-2.0.so.0")"
gobject_library="$(readlink -f "$stage/usr/lib/libgobject-2.0.so.0")"
gio_library="$(readlink -f "$stage/usr/lib/libgio-2.0.so.0")"
for pair in "$glib_library:libglib-2.0.so.0" \
            "$gobject_library:libgobject-2.0.so.0" \
            "$gio_library:libgio-2.0.so.0"; do
    library="${pair%%:*}"
    soname="${pair#*:}"
    grep -Fq "Library soname: [$soname]" < <(readelf -d "$library") ||
        die "Wrong GLib SONAME: $library"
    grep -Fq 'Shared library: [libc.so]' < <(readelf -d "$library") ||
        die "GLib library is not linked against musl: $library"
done
grep -Fq 'Shared library: [libpcre2-8.so.0]' < <(readelf -d "$glib_library") ||
    die 'GLib is not linked against packaged PCRE2.'
grep -Fq 'Shared library: [libffi.so.8]' < <(readelf -d "$gobject_library") ||
    die 'GObject is not linked against packaged libffi.'

package="$root/build/system-packages/glib-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name glib --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'libffi>=3.5.2' --depends 'pcre2>=10.48' \
    --depends 'zlib>=1.3.2' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'GLIB_PACKAGE_READY: %s\n' "$package"
