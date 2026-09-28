#!/usr/bin/env bash
# Build X.Org's VESA CVT mode generator for the NekoOS musl runtime.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxcvt/build.sh'

version=0.1.3
archive=libxcvt-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/lib/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg-announce@lists.x.org/msg01780.html
sha256=a929998a8767de7dfa36d6da4751cdbeef34ed630714f2f4a767b351f2442e01
sha512=2fecc784375e69b6e8e46608618a5f5a8ad20ecd5229fd093883fe401dd6ea231d8b77c6753756fff01f3040bef2db60a042d40fc349769ef5348e5cd9ed1f28
meson_version=1.10.1
meson_url=https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz
meson_sha256=c42296f12db316a4515b9375a5df330f2e751ccdd4f608430d41d7d6210e4317

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar python3 ninja ar strip readelf strings; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

fetch() {
    local url="$1" hash="$2" file
    file="$root/cache/sources/${url##*/}"
    if [[ ! -f "$file" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            -o "$file.part" "$url"
        printf '%s  %s\n' "$hash" "$file.part" | sha256sum -c -
        mv -- "$file.part" "$file"
    fi
    printf '%s  %s\n' "$hash" "$file" | sha256sum -c -
}

fetch "$meson_url" "$meson_sha256"
fetch "$url" "$sha256"
printf '%s  %s\n' "$sha512" "$root/cache/sources/$archive" | sha512sum -c -

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

work="$root/build/system-package-build/libxcvt-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$root/cache/sources/$archive" -C "$work/sources"
source_dir="$work/sources/libxcvt-$version"
stage="$work/stage"
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

CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    "${meson[@]}" setup "$work/build" "$source_dir" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared
"${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
install -Dm 644 "$source_dir/COPYING" "$stage/usr/share/licenses/libxcvt/COPYING"

library="$stage/usr/lib/libxcvt.so.$version"
[[ -f "$library" && -L "$stage/usr/lib/libxcvt.so" &&
   -L "$stage/usr/lib/libxcvt.so.0" &&
   -f "$stage/usr/include/libxcvt/libxcvt.h" &&
   -f "$stage/usr/lib/pkgconfig/libxcvt.pc" &&
   -f "$stage/usr/bin/cvt" ]] || die 'libxcvt runtime or development files are missing.'
dynamic="$(readelf -d "$library")"
grep -Fq 'Library soname: [libxcvt.so.0]' <<< "$dynamic" || die 'libxcvt SONAME is wrong.'
grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" || die 'libxcvt is not linked against musl.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
   strings "$library" | grep -F "$root/" >/dev/null; then
    die 'libxcvt contains a host runtime dependency or build path.'
fi
program_dynamic="$(readelf -d "$stage/usr/bin/cvt")"
grep -Fq 'Shared library: [libxcvt.so.0]' <<< "$program_dynamic" ||
    die 'cvt does not use the packaged libxcvt shared library.'
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$program_dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$program_dynamic"; then
    die 'cvt contains a host runtime dependency or build path.'
fi
readelf -l "$stage/usr/bin/cvt" | grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'cvt does not use the NekoOS musl interpreter.'

package="$root/build/system-packages/libxcvt-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name libxcvt --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'LIBXCVT_PACKAGE_READY: %s\n' "$package"
