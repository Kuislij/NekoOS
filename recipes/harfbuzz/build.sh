#!/usr/bin/env bash
# Build the OpenType shaping engine in upstream's no-libstdc++ mode.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/harfbuzz/build.sh'
version=12.3.0
archive=harfbuzz-$version.tar.xz
url=https://github.com/harfbuzz/harfbuzz/releases/download/$version/$archive
# SHA-256 published by the upstream GitHub release asset API.
sha256=8660ebd3c27d9407fc8433b5d172bafba5f0317cb0bb4339f28e5370c93d42b7
glib_sha256=8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90
[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 && -f "$meson" &&
   "$(python3 "$meson" --version)" == 1.10.1 ]] || die 'Build the pinned host pkgconf and Meson first.'
for tool in curl sha256sum tar python3 ninja gcc g++ ar strip readelf strings nm find; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done
[[ "$(gcc -dumpfullversion)" == "$(g++ -dumpfullversion)" &&
   "$(gcc -dumpmachine)" == "$(g++ -dumpmachine)" ]] ||
    die 'The build-host gcc and g++ must be matching compiler installations.'
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
prerequisites=(dejavu-fonts-2.37.nspkg freetype-2.14.3.nspkg glib-2.84.4.nspkg
    libffi-3.5.2.nspkg libpng-1.6.58.nspkg pcre2-10.48.nspkg zlib-1.3.2.nspkg)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done
work="$root/build/system-package-build/harfbuzz-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] || die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" "$work/host-tools" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" --root "$sysroot" >/dev/null
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/harfbuzz-$version"
tar -xOf "$glib_source" glib-2.84.4/gobject/glib-mkenums.in |
    sed "s|@PYTHON@|$(command -v python3)|g; s|@VERSION@|2.84.4|g" > "$work/host-tools/glib-mkenums"
chmod +x "$work/host-tools/glib-mkenums"

# Only compiler-matched C++ template headers are exposed. C headers continue
# to come exclusively from musl via the existing specs. Bypass the build-host
# libstdc++ GNU-libc configuration header; neither libstdc++ nor its ABI is linked.
# HarfBuzz's own no-libstdc++ mode deliberately supports C linkage for these
# header-only templates and supplies placement-new itself.
mapfile -t cpp_header_dirs < <(g++ -E -x c++ - -v </dev/null 2>&1 |
    sed -n '/#include <\.\.\.> search starts here:/,/End of search list./p' |
    sed -n 's/^ \(.*\/c++\/[^ ]*\)$/\1/p')
(( ${#cpp_header_dirs[@]} >= 2 )) || die 'Could not locate compiler-matched C++ template headers.'
{
    printf '#!/usr/bin/env bash\nexec %q -specs %q ' "$(command -v gcc)" "$root/build/host-musl-gcc.specs"
    for directory in "${cpp_header_dirs[@]}"; do
        [[ -d "$directory" ]] || die "C++ template header directory is missing: $directory"
        printf -- '-isystem %q ' "$directory"
    done
    printf '%s\n' '-D_GLIBCXX_OS_DEFINES=1 -D_GLIBCXX_NO_OBSOLETE_ISINF_ISNAN_DYNAMIC=1 "$@"'
} > "$work/host-tools/musl-cxx"
chmod +x "$work/host-tools/musl-cxx"
cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
cpp = '$work/host-tools/musl-cxx'
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
        -Dauto_features=disabled -Dwith_libstdcxx=false -Dglib=enabled \
        -Dgobject=enabled -Dfreetype=enabled -Dcairo=disabled \
        -Dtests=disabled -Dutilities=disabled -Ddocs=disabled -Dintrospection=disabled
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/harfbuzz/COPYING"
install -Dm 644 "$src/src/ms-use/COPYING" "$stage/usr/share/licenses/harfbuzz/ms-use-COPYING"
for component in harfbuzz harfbuzz-subset harfbuzz-gobject; do
    library="$(readlink -f "$stage/usr/lib/lib$component.so.0")"
    [[ -f "$library" && -L "$stage/usr/lib/lib$component.so" &&
       -f "$stage/usr/lib/pkgconfig/$component.pc" ]] || die "HarfBuzz component $component is missing."
    strip --strip-unneeded "$library"
    dynamic="$(readelf -d "$library")"
    grep -Fq "Library soname: [lib$component.so.0]" <<< "$dynamic" || die 'HarfBuzz SONAME is wrong.'
    if [[ "$component" == harfbuzz-gobject ]]; then
        # This thin binding has no direct libc calls; musl is supplied through
        # the required core/GObject dependencies with --as-needed linking.
        for needed in libharfbuzz.so.0 libgobject-2.0.so.0; do
            grep -Fq "Shared library: [$needed]" <<< "$dynamic" || die 'HarfBuzz GObject binding is missing its packaged runtime.'
        done
    else
        grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'HarfBuzz is not linked against musl.'
    fi
    if grep -Eq '\((RPATH|RUNPATH)\)|Shared library: \[(libc.so.6|libstdc\+\+|libgcc_s)' <<< "$dynamic" ||
       nm -D --undefined-only "$library" | grep -vE ' w __cxa_finalize$' |
           grep -Eq '__cxa|_Unwind|[[:space:]]_Z|GLIBC_' ||
       strings "$library" | grep -F "$root/" >/dev/null; then
        die "HarfBuzz contains a host runtime/C++ ABI dependency or build path: $library"
    fi
done
[[ -f "$stage/usr/include/harfbuzz/hb.h" && -f "$stage/usr/include/harfbuzz/hb-ft.h" &&
   -f "$stage/usr/include/harfbuzz/hb-gobject.h" ]] || die 'HarfBuzz development headers are missing.'
(
    export PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig:$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    unset PKG_CONFIG_PATH
    cflags_text="$("$pkgconf" --cflags harfbuzz-gobject freetype2)"
    libs_text="$("$pkgconf" --libs harfbuzz-gobject freetype2)"
    read -r -a flags <<< "$cflags_text"
    read -r -a libs <<< "$libs_text"
    "$root/scripts/host-musl-gcc.sh" "${flags[@]}" -I"$stage/usr/include/harfbuzz" \
        -L"$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib:$sysroot/usr/lib" \
        "$root/recipes/harfbuzz/smoke.c" "${libs[@]}" -o "$work/harfbuzz-smoke"
)
"$root/build/toolchain-root/usr/lib/libc.so" --library-path "$stage/usr/lib:$sysroot/usr/lib" \
    "$work/harfbuzz-smoke" "$sysroot/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
package="$root/build/system-packages/harfbuzz-$version.nspkg"
python3 "$root/tools/system_package.py" build --root "$stage" --name harfbuzz \
    --version "$version" --arch x86_64 --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'freetype>=2.14.3' --depends 'glib>=2.84.4' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'HARFBUZZ_PACKAGE_READY: %s\n' "$package"
