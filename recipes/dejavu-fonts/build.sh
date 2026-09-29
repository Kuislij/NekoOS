#!/usr/bin/env bash
# Install the pinned DejaVu scalable fonts for Fontconfig/Xft and future GTK.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/dejavu-fonts/build.sh'

version=2.37
archive=dejavu-fonts-ttf-$version.tar.bz2
url=https://sourceforge.net/projects/dejavu/files/dejavu/$version/$archive/download
# Official DejaVu download page: https://dejavu-fonts.github.io/Download.html
sha256=fa9ca4d13871dd122f61258a80d01751d603b4d3ee14095d65453b4e846e17d7

for tool in curl sha256sum tar install python3 od; do
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

work="$root/build/system-package-build/dejavu-fonts-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$root/build/system-packages"
tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/dejavu-fonts-ttf-$version"
stage="$work/stage"
fontdir="$stage/usr/share/fonts/truetype/dejavu"
mkdir -p "$fontdir"

fonts=("$src"/ttf/*.ttf)
[[ ${#fonts[@]} -eq 22 && -f "${fonts[0]}" ]] ||
    die 'The official DejaVu archive does not contain the expected 22 TrueType fonts.'
for font in "${fonts[@]}"; do
    # The pinned archive contains TrueType sfnt files, not arbitrary downloads.
    [[ "$(od -An -tx1 -N4 "$font")" == *'00 01 00 00'* ]] ||
        die "Invalid TrueType signature: $font"
    install -m 644 "$font" "$fontdir/${font##*/}"
done
for required in DejaVuSans.ttf DejaVuSans-Bold.ttf DejaVuSansMono.ttf \
                DejaVuSerif.ttf DejaVuMathTeXGyre.ttf; do
    [[ -s "$fontdir/$required" ]] || die "Missing font: $required"
done
install -Dm 644 "$src/LICENSE" "$stage/usr/share/licenses/dejavu-fonts/LICENSE"

package="$root/build/system-packages/dejavu-fonts-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name dejavu-fonts --version "$version" --arch x86_64 \
    --license NOASSERTION --source-sha256 "$sha256" --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'DEJAVU_FONTS_PACKAGE_READY: %s\n' "$package"
