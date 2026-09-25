#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash os iso'
command -v grub-mkrescue >/dev/null 2>&1 || die 'grub-mkrescue is missing. Run bash os doctor --install.'
command -v xorriso >/dev/null 2>&1 || die 'xorriso is missing. Run bash os doctor --install.'
[[ -d /usr/lib/grub/i386-pc ]] || die 'GRUB BIOS modules are missing. Install grub-pc-bin.'
images="$root/out/images"
for file in bzImage initramfs.cpio.gz SHA256SUMS; do
    [[ -f "$images/$file" && ! -L "$images/$file" ]] || die "Missing or unsafe image: $file. Run bash os build."
done
(cd "$images" && sha256sum -c SHA256SUMS)
stage="$root/build/iso-root"
[[ ! -L "$stage" ]] || die 'ISO staging directory must not be a symlink.'
rm -rf -- "$stage"
mkdir -p "$stage/boot/grub"
install -m 644 "$root/boot/grub/grub.cfg" "$stage/boot/grub/grub.cfg"
install -m 644 "$images/bzImage" "$stage/boot/bzImage"
install -m 644 "$images/initramfs.cpio.gz" "$stage/boot/initramfs.cpio.gz"
iso="$images/NekoOS.iso"
[[ ! -L "$iso" && ! -L "$iso.new" && ! -L "$images/ISO_SHA256SUMS" ]] || die 'ISO outputs must not be symlinks.'
grub-mkrescue -o "$iso.new" "$stage"
mv -- "$iso.new" "$iso"
(cd "$images" && sha256sum NekoOS.iso > ISO_SHA256SUMS)
echo "ISO_READY: $iso"
