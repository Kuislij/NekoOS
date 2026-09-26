#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash os system-image'
disk="$root/out/disks/system.img"
template="$root/out/images/system-template.img"
[[ -f "$template" && ! -L "$template" ]] || die 'Build the system template first: bash os build.'
[[ -f "$root/out/images/SHA256SUMS" && ! -L "$root/out/images/SHA256SUMS" ]] || die 'Image checksums are missing or unsafe.'
grep -Eq '^[0-9a-f]{64}  system-template[.]img$' "$root/out/images/SHA256SUMS" || die 'System template checksum is missing.'
(cd "$root/out/images" && sha256sum -c SHA256SUMS --ignore-missing)
exec 7>"$root/out/disks/.system-create-lock"
flock -n 7 || die 'Another system disk creation is in progress.'
[[ ! -L "$disk" ]] || die 'System disk must not be a symlink.'
if [[ -e "$disk" ]]; then
    [[ -f "$disk" ]] || die 'System disk path is not a regular file.'
    [[ "$(blkid -p -s TYPE -o value "$disk")" == ext4 ]] || die 'Existing system disk is not ext4.'
    [[ "$(blkid -p -s LABEL -o value "$disk")" == NEKO_SYSTEM ]] || die 'Existing system disk has the wrong label.'
    echo "SYSTEM_DISK_READY: $disk (existing; contents preserved)"
    exit 0
fi
temp="$(mktemp "$root/out/disks/system.img.XXXXXXXX")"
trap 'rm -f -- "$temp"' EXIT
cp --sparse=always -- "$template" "$temp"
[[ "$(blkid -p -s TYPE -o value "$temp")" == ext4 ]] || die 'New system disk verification failed.'
[[ "$(blkid -p -s LABEL -o value "$temp")" == NEKO_SYSTEM ]] || die 'New system disk label is wrong.'
[[ ! -e "$disk" ]] || die 'System disk appeared during creation; leaving it untouched.'
mv --no-clobber -- "$temp" "$disk"
trap - EXIT
echo "SYSTEM_DISK_READY: $disk (new writable ext4 disk)"
