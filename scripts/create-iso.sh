#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || [[ $# == 1 && "${1:-}" == --system ]] || die 'Usage: bash os iso [--system]'
system=off
[[ ${1:-} != --system ]] || system=on
command -v grub-mkrescue >/dev/null 2>&1 || die 'grub-mkrescue is missing. Run bash os doctor --install.'
command -v xorriso >/dev/null 2>&1 || die 'xorriso is missing. Run bash os doctor --install.'
[[ -d /usr/lib/grub/i386-pc ]] || die 'GRUB BIOS modules are missing. Install grub-pc-bin.'
exec 7>"$root/build/.iso-lock"
flock -n 7 || die 'Another ISO build is running.'
images="$root/out/images"
for file in bzImage initramfs.cpio.gz bootstrap.cpio.gz SHA256SUMS; do
    [[ -f "$images/$file" && ! -L "$images/$file" ]] || die "Missing or unsafe image: $file. Run bash os build."
done
(cd "$images" && sha256sum -c SHA256SUMS)
stage="$root/build/iso-root"
[[ ! -L "$stage" ]] || die 'ISO staging directory must not be a symlink.'
rm -rf -- "$stage"
mkdir -p "$stage/boot/grub"
install -m 644 "$root/boot/grub/grub.cfg" "$stage/boot/grub/grub.cfg"
if [[ "$system" == on ]]; then
    sed -i 's/^set default=0$/set default=1/' "$stage/boot/grub/grub.cfg"
    grep -Fqx 'set default=1' "$stage/boot/grub/grub.cfg" || die 'Could not select system disk entry.'
fi
install -m 644 "$images/bzImage" "$stage/boot/bzImage"
install -m 644 "$images/initramfs.cpio.gz" "$stage/boot/initramfs.cpio.gz"
install -m 644 "$images/bootstrap.cpio.gz" "$stage/boot/bootstrap.cpio.gz"
iso_name=NekoOS.iso
checksum_name=ISO_SHA256SUMS
if [[ "$system" == on ]]; then
    iso_name=NekoOS-system.iso
    checksum_name=SYSTEM_ISO_SHA256SUMS
fi
iso="$images/$iso_name"
[[ ! -L "$iso" && ! -L "$iso.new" && ! -L "$images/$checksum_name" ]] || die 'ISO outputs must not be symlinks.'
grub-mkrescue -o "$iso.new" "$stage"
mv -- "$iso.new" "$iso"
(cd "$images" && sha256sum "$iso_name" > "$checksum_name")
echo "ISO_READY: $iso"
