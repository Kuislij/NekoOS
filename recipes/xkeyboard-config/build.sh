#!/usr/bin/env bash
# Package the generated X.Org keyboard rules, layouts and symbols for NekoOS.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xkeyboard-config/build.sh'

version=2.48
archive=xkeyboard-config-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config/$archive
# X.Org release announcement: https://www.mail-archive.com/xorg-announce@lists.x.org/msg01915.html
sha256=b77041324f0109f77161ee43743fe04baa485866af8460d31e476ad3f7648fd5
sha512=2c24f9cca97b8863ff2e71fc3780e9c3e22e4486c80d45022e2208d559bdb40824bdb8a4037e0d5690900b6e080ddef4eacfc8bff843e04ba5ab86940f1fb6ea
meson_version=1.10.1
meson_url=https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz
meson_sha256=c42296f12db316a4515b9375a5df330f2e751ccdd4f608430d41d7d6210e4317

for tool in curl sha256sum sha512sum tar python3 perl ninja ln; do
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

work="$root/build/system-package-build/xkeyboard-config-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$root/cache/sources/$archive" -C "$work/sources"
source_dir="$work/sources/xkeyboard-config-$version"
stage="$work/stage"

# This is data only. Rules are generated with host Python/Perl, then installed
# into a versioned XKB tree; no host executables or shared libraries are staged.
"${meson[@]}" setup "$work/build" "$source_dir" \
    --prefix=/usr --datadir=share --buildtype=release --wrap-mode=nofallback \
    -Dnls=false -Dnon-latin-layouts-list=false \
    -Dcompat-rules=true -Dxorg-rules-symlinks=true
"${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
install -Dm 644 "$source_dir/COPYING" \
    "$stage/usr/share/licenses/xkeyboard-config/COPYING"

# Meson emits an absolute legacy symlink; NSPKG requires symlinks to remain
# inside /usr and be relative to their package location.
[[ -L "$stage/usr/share/X11/xkb" ]] || die 'The legacy XKB path is missing.'
rm -- "$stage/usr/share/X11/xkb"
ln -s ../xkeyboard-config-2 "$stage/usr/share/X11/xkb"

xkb="$stage/usr/share/xkeyboard-config-2"
[[ -f "$xkb/rules/evdev" && -f "$xkb/rules/evdev.lst" &&
   -f "$xkb/rules/evdev.xml" && -f "$xkb/keycodes/evdev" &&
   -f "$xkb/symbols/us" && -f "$xkb/symbols/ru" &&
   -f "$xkb/types/complete" && -f "$xkb/compat/complete" &&
   -L "$xkb/rules/xorg" &&
   "$(readlink "$stage/usr/share/X11/xkb")" == '../xkeyboard-config-2' &&
   -f "$stage/usr/share/pkgconfig/xkeyboard-config-2.pc" ]] ||
    die 'XKB rules, layouts, symbols, or legacy link are incomplete.'

python3 - "$stage" <<'PY'
import os
from pathlib import Path
import sys

for directory, _, names in os.walk(sys.argv[1], followlinks=False):
    for name in names:
        path = Path(directory, name)
        if path.is_symlink():
            continue
        with path.open('rb') as stream:
            if stream.read(4) == b'\x7fELF':
                raise SystemExit(f'Unexpected executable in XKB data package: {path}')
PY

package="$root/build/system-packages/xkeyboard-config-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name xkeyboard-config --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'XKEYBOARD_CONFIG_PACKAGE_READY: %s\n' "$package"
