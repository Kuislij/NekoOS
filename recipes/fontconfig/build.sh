#!/usr/bin/env bash
# Build font discovery, matching and configuration for the NekoOS musl desktop.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/fontconfig/build.sh'

version=2.17.1
archive=fontconfig-$version.tar.xz
url=https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/$version/$archive
sha256=9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541
sha512=c09c1f041f61ee0d220ff906a86b5c4b329106dc96f8c04b23f8fdeb480df626717fe3613bccb41cb39e86334078139322710377f5ddaa3abe48569e798161c9

gperf_version=3.3
gperf_archive=gperf-$gperf_version.tar.gz
gperf_url=https://ftp.gnu.org/gnu/gperf/$gperf_archive
# Published in the official GNU gperf 3.3 release announcement.
gperf_sha256=fd87e0aba7e43ae054837afd6cd4db03a3f2693deb3619085e6ed9d8d9604ad8
gperf_sha512=246b75b8ce7d77d6a8725cd15f1cf2e68da404812573af1d5bf32dbe6ad4228f48757baefc77bcb1f5597c2397043c04d31d8a04ab507bfa7a80f85e1ab6045f

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
meson="$root/build/host-tools/meson-1.10.1/meson.py"
[[ -f "$meson" && "$(python3 "$meson" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/pixman/build.sh).'
for tool in curl sha256sum sha512sum tar make g++ python3 ninja ar strip readelf strings find; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

fetch() {
    local source_url="$1" expected_sha256="$2" expected_sha512="$3" source_file
    source_file="$root/cache/sources/${source_url##*/}"
    if [[ ! -f "$source_file" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            -o "$source_file.part" "$source_url"
        printf '%s  %s\n' "$expected_sha256" "$source_file.part" | sha256sum -c -
        mv -- "$source_file.part" "$source_file"
    fi
    printf '%s  %s\n' "$expected_sha256" "$source_file" | sha256sum -c -
    printf '%s  %s\n' "$expected_sha512" "$source_file" | sha512sum -c -
}
fetch "$gperf_url" "$gperf_sha256" "$gperf_sha512"
fetch "$url" "$sha256" "$sha512"

# Fontconfig generates hash tables with gperf. Build that host-only tool from
# pinned GNU source so host-distribution versions cannot change the output.
gperf_work="$root/build/host-tools/gperf-$gperf_version"
[[ ! -L "$root/build/host-tools" && ! -L "$gperf_work" ]] ||
    die 'Host gperf work directory must not be a symlink.'
if [[ ! -x "$gperf_work/install/bin/gperf" ]]; then
    rm -rf -- "$gperf_work"
    mkdir -p "$gperf_work/sources" "$gperf_work/build"
    tar --no-same-owner -xf "$root/cache/sources/$gperf_archive" -C "$gperf_work/sources"
    (
        cd "$gperf_work/build"
        "$gperf_work/sources/gperf-$gperf_version/configure" \
            --prefix="$gperf_work/install"
        make -j "${JOBS:-4}"
        make install
    )
fi
gperf="$gperf_work/install/bin/gperf"
"$gperf" --version | grep -Fq "GNU gperf $gperf_version" ||
    die 'Wrong pinned host gperf version.'

prerequisites=(
    expat-2.8.5.nspkg
    freetype-2.14.3.nspkg
    zlib-1.3.2.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/fontconfig-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/sysroot" "$work/stage" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/expat.pc" &&
   -f "$sysroot/usr/lib/pkgconfig/freetype2.pc" &&
   -f "$sysroot/usr/include/expat.h" &&
   -f "$sysroot/usr/include/freetype2/ft2build.h" ]] ||
    die 'Fontconfig prerequisite development files are missing.'

tar --no-same-owner -xf "$root/cache/sources/$archive" -C "$work/sources"
src="$work/sources/fontconfig-$version"
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
    export PATH="$gperf_work/install/bin:$PATH"
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    python3 "$meson" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --sysconfdir=/usr/etc --localstatedir=/var \
        --buildtype=release --wrap-mode=nofallback -Ddefault_library=shared \
        -Dtests=disabled -Ddoc=disabled -Dnls=disabled -Dtools=enabled \
        -Dxml-backend=expat -Dcache-build=disabled -Dfontations=disabled \
        -Dbitmap-conf=yes -Ddefault-fonts-dirs=/usr/share/fonts \
        -Dadditional-fonts-dirs=no -Dcache-dir=/var/cache/fontconfig \
        -Dbaseconfig-dir=/usr/etc/fonts \
        -Dconfig-dir=/usr/etc/fonts/conf.d \
        -Dtemplate-dir=/usr/share/fontconfig/conf.avail
    python3 "$meson" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" python3 "$meson" install -C "$work/build" --no-rebuild
)

# The guest creates /var/cache at runtime; NSPKG packages contain only /usr.
[[ ! -L "$stage/var" ]] || die 'Fontconfig cache directory must not be a symlink.'
rm -rf -- "$stage/var"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/fontconfig/COPYING"

library="$stage/usr/lib/libfontconfig.so.1.16.0"
[[ -f "$library" && -L "$stage/usr/lib/libfontconfig.so.1" &&
   -L "$stage/usr/lib/libfontconfig.so" &&
   -f "$stage/usr/include/fontconfig/fontconfig.h" &&
   -f "$stage/usr/lib/pkgconfig/fontconfig.pc" &&
   -f "$stage/usr/etc/fonts/fonts.conf" &&
   -L "$stage/usr/etc/fonts/conf.d/70-yes-bitmaps.conf" &&
   -f "$stage/usr/share/fontconfig/conf.avail/70-yes-bitmaps.conf" &&
   -f "$stage/usr/bin/fc-match" && -f "$stage/usr/bin/fc-list" &&
   -f "$stage/usr/bin/fc-cache" ]] ||
    die 'Fontconfig library, configuration, CLI or development files are missing.'
grep -Fq '<dir>/usr/share/fonts</dir>' "$stage/usr/etc/fonts/fonts.conf" ||
    die 'Fontconfig does not scan NekoOS system fonts.'

while IFS= read -r -d '' binary; do
    [[ "$(readelf -h "$binary" 2>/dev/null | sed -n 's/.*Class:[[:space:]]*//p' | head -1)" == ELF64 ]] || continue
    strip --strip-unneeded "$binary"
    dynamic="$(readelf -d "$binary")"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "Fontconfig contains a host dependency or build path: $binary"
    fi
    if strings "$binary" | grep -F "$root/" >/dev/null; then
        die "Fontconfig contains an absolute build path: $binary"
    fi
done < <(find "$stage/usr" -type f -print0)
for binary in "$stage"/usr/bin/*; do
    [[ -f "$binary" ]] || continue
    grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
        < <(readelf -l "$binary") ||
        die "Fontconfig utility lacks the NekoOS musl interpreter: $binary"
done
dynamic="$(readelf -d "$library")"
for needed in 'Library soname: [libfontconfig.so.1]' \
              'Shared library: [libfreetype.so.6]' \
              'Shared library: [libexpat.so.1]' \
              'Shared library: [libc.so]'; do
    grep -Fq "$needed" <<< "$dynamic" ||
        die "Fontconfig shared library is missing $needed"
done

package="$root/build/system-packages/fontconfig-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name fontconfig --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'expat>=2.8.5' --depends 'freetype>=2.14.3' \
    --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'FONTCONFIG_PACKAGE_READY: %s\n' "$package"
