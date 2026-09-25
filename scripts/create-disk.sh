#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash os image'
disk="$root/out/disks/state.img"
exec 8>"$root/out/disks/.create-lock"
flock -n 8 || die 'Another virtual disk creation is in progress.'
[[ ! -L "$disk" ]] || die 'Virtual disk must not be a symlink.'
if [[ -e "$disk" ]]; then
    [[ -f "$disk" ]] || die 'Virtual disk path is not a regular file.'
    [[ "$(blkid -p -s TYPE -o value "$disk")" == ext4 ]] || die 'Existing virtual disk is not ext4.'
    echo "DISK_READY: $disk (existing; contents preserved)"
    exit 0
fi
temp="$(mktemp "$root/out/disks/state.img.XXXXXXXX")"
trap 'rm -f -- "$temp"' EXIT
qemu-img create -f raw "$temp" 512M
mkfs.ext4 -F -q -m 0 -L NEKO_STATE "$temp"
[[ "$(blkid -p -s TYPE -o value "$temp")" == ext4 ]] || die 'New virtual disk verification failed.'
[[ ! -e "$disk" ]] || die 'Virtual disk appeared during creation; leaving it untouched.'
mv --no-clobber -- "$temp" "$disk"
trap - EXIT
echo "DISK_READY: $disk (new 512 MiB sparse ext4 file)"
