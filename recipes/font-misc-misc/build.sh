#!/usr/bin/env bash
# Package two upstream X.Org bitmap fonts for the first local X server.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/font-misc-misc/build.sh'

version=1.1.3
archive=font-misc-misc-$version.tar.xz
url=https://xorg.freedesktop.org/archive/individual/font/$archive
# X.Org announcement: https://lists.x.org/archives/xorg-announce/2023-February/003363.html
sha256=79abe361f58bb21ade9f565898e486300ce1cc621d5285bec26e14b6a8618fed
sha512=fac4bfda0e4189d1a9999abc47bdd404f2beeec5301da190d92afc2176cd344789b7223c1b2f4748bd0efe1b9a81fa7f13f7037015d5d800480fa2236f369b48

for tool in curl sha256sum sha512sum tar grep head wc install python3; do
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

work="$root/build/system-package-build/font-misc-misc-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/font-misc-misc-$version"
stage="$work/stage"
fontdir="$stage/usr/share/fonts/X11/misc"
mkdir -p "$fontdir"

# The verified upstream BDF files can be read directly by libXfont2's BDF
# backend. This avoids a host bdftopcf/mkfontdir dependency for the first Xorg
# milestone; fonts.dir uses each font's own XLFD name from the BDF header.
fonts=(6x13.bdf 9x15.bdf)
printf '%d\n' "${#fonts[@]}" > "$fontdir/fonts.dir"
for font in "${fonts[@]}"; do
    source_font="$src/$font"
    [[ -f "$source_font" ]] || die "Upstream font is missing: $font"
    xlfd_line="$(grep -m 1 '^FONT ' "$source_font")"
    [[ "$xlfd_line" == 'FONT -'* ]] || die "Invalid XLFD declaration: $font"
    install -m 644 "$source_font" "$fontdir/$font"
    printf '%s %s\n' "$font" "${xlfd_line#FONT }" >> "$fontdir/fonts.dir"
done

small_xlfd="$(grep -m 1 '^FONT ' "$src/6x13.bdf")"
printf 'fixed %s\n' "${small_xlfd#FONT }" > "$fontdir/fonts.alias"
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/font-misc-misc/COPYING"
[[ "$(head -n 1 "$fontdir/fonts.dir")" == 2 &&
   "$(wc -l < "$fontdir/fonts.dir")" == 3 &&
   "$(wc -l < "$fontdir/fonts.alias")" == 1 ]] ||
    die 'The X11 bitmap font index is incomplete.'

package="$root/build/system-packages/font-misc-misc-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name font-misc-misc --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'FONT_MISC_MISC_PACKAGE_READY: %s\n' "$package"
