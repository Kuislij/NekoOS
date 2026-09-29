#!/usr/bin/env bash
# Run the packaged musl Fontconfig tools against packaged NekoOS PCF fonts.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/fontconfig/smoke.sh'

work="$root/build/system-package-build/fontconfig-2.17.1"
loader="$root/build/toolchain-root/usr/lib/libc.so"
[[ -x "$loader" && -d "$work" ]] ||
    die 'Build the Fontconfig package before running its font lookup smoke test.'

packages=(
    zlib-1.3.2.nspkg
    expat-2.8.5.nspkg
    freetype-2.14.3.nspkg
    fontconfig-2.17.1.nspkg
    font-misc-misc-1.1.3.nspkg
)
archives=()
for package in "${packages[@]}"; do
    file="$root/build/system-packages/$package"
    [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
    archives+=("$file")
done

smoke_root="$(mktemp -d "$work/smoke.XXXXXXXX")"
trap 'rm -rf -- "$smoke_root"' EXIT
python3 "$root/tools/system_package.py" install "${archives[@]}" \
    --root "$smoke_root" >/dev/null
[[ -f "$smoke_root/usr/share/fonts/X11/misc/6x13.pcf" &&
   -f "$smoke_root/usr/share/fonts/X11/misc/9x15.pcf" &&
   -f "$smoke_root/usr/etc/fonts/fonts.conf" ]] ||
    die 'Packaged fonts or Fontconfig configuration are missing.'

# FONTCONFIG_SYSROOT makes the installed /usr paths resolve inside this isolated
# package tree, without falling back to any fonts installed on the WSL host.
export FONTCONFIG_SYSROOT="$smoke_root"
export XDG_CACHE_HOME="$smoke_root/cache"
unset FONTCONFIG_FILE FONTCONFIG_PATH
font_list="$("$loader" --library-path "$smoke_root/usr/lib" \
    "$smoke_root/usr/bin/fc-list" -f '%{family}: %{file}\n')"
grep -Fxq 'Fixed: /usr/share/fonts/X11/misc/6x13.pcf' <<< "$font_list" ||
    die 'Fontconfig did not discover the packaged 6x13 PCF font.'
grep -Fxq 'Fixed: /usr/share/fonts/X11/misc/9x15.pcf' <<< "$font_list" ||
    die 'Fontconfig did not discover the packaged 9x15 PCF font.'
[[ "$(wc -l <<< "$font_list")" == 2 ]] ||
    die "Fontconfig discovered unexpected fonts: $font_list"

match="$("$loader" --library-path "$smoke_root/usr/lib" \
    "$smoke_root/usr/bin/fc-match" -f '%{file}' fixed)"
[[ "$match" == /usr/share/fonts/X11/misc/6x13.pcf ]] ||
    die "Fontconfig resolved fixed to an unexpected font: $match"
printf 'FONTCONFIG_FONTS_READY: %s\n' "$match"
