#!/usr/bin/env bash
# Build upstream evilwm as the first real X11 window manager for NekoOS.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/evilwm/build.sh'

version=1.5
archive=evilwm-$version.tar.gz
url=https://www.6809.org.uk/evilwm/dl/$archive
sha256=6104852413e6d50669361dcadda5a25d39e2b2b0c95a6384022c905957a2740f
sha512=91495841ec78d350253553c7970fe93097c6634f80d13c30a1e0329d82ab53b131ab1b7946b29837b191c4d450567bd3f3f4387ace0280f969fe14a874d5d304

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
for tool in curl sha256sum sha512sum tar make readelf strip strings; do
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
    xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxext-1.3.7.nspkg
    libxrender-0.9.12.nspkg
    libxrandr-1.5.5.nspkg
)
archives=()
for package in "${prerequisites[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    python3 "$root/tools/system_package.py" verify "$file" >/dev/null
    archives+=("$file")
done

work="$root/build/system-package-build/evilwm-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" \
    "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/include/X11/Xlib.h" &&
   -f "$sysroot/usr/include/X11/extensions/Xrandr.h" &&
   -f "$sysroot/usr/lib/libXrandr.so" &&
   -f "$sysroot/usr/lib/libXext.so" ]] ||
    die 'X11 and RandR prerequisites did not install completely.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/evilwm-$version"
make -C "$src" -j "${JOBS:-4}" \
    CC="$root/scripts/host-musl-gcc.sh" \
    CPPFLAGS="-I$sysroot/usr/include" \
    CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
    LDFLAGS="-L$sysroot/usr/lib -Wl,-rpath-link,$sysroot/usr/lib"
make -C "$src" DESTDIR="$stage" install
binary="$stage/usr/bin/evilwm"
[[ -f "$binary" && -f "$stage/usr/share/man/man1/evilwm.1" ]] ||
    die 'evilwm executable or manual is missing.'
install -Dm 644 "$src/README" "$stage/usr/share/licenses/evilwm/README"
strip --strip-unneeded "$binary"

interpreter="$(readelf -l "$binary")"
grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' <<< "$interpreter" ||
    die 'evilwm does not use the NekoOS musl loader.'
dynamic="$(readelf -d "$binary")"
for needed in libX11.so.6 libXext.so.6 libXrandr.so.2 libc.so; do
    grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
        die "evilwm is missing expected runtime dependency $needed."
done
if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
   grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
    die 'evilwm contains a host runtime dependency or build path.'
fi
if strings "$binary" | grep -F "$root/" >/dev/null; then
    die 'evilwm contains an absolute build path.'
fi

package="$root/build/system-packages/evilwm-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name evilwm --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" \
    --depends 'libx11>=1.8.13' --depends 'libxext>=1.3.7' \
    --depends 'libxrandr>=1.5.5' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'EVILWM_PACKAGE_READY: %s\n' "$package"
