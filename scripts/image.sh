#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ -n "${FAKEROOTKEY:-}" ]] || die 'Internal command: invoke through bash os build.'
[[ $# == 1 && -f "$1" ]] || die 'Expected a built BusyBox binary.'
stage="$root/build/rootfs"
# Exact generated path under the verified build directory; never accept a caller path.
rm -rf -- "$stage"
mkdir -p "$stage"/{bin,sbin,etc,proc,sys,dev/pts,tmp,run,usr/bin,usr/sbin,var,home,root}
install -m 755 "$1" "$stage/bin/busybox"
"$1" --list > "$root/build/busybox-applets.txt"
while IFS= read -r applet; do
    [[ "$applet" == busybox ]] || ln -s busybox "$stage/bin/$applet"
done < "$root/build/busybox-applets.txt"
for applet in sh mount mkdir sleep; do
    [[ -x "$stage/bin/$applet" ]] || die "Missing required applet: $applet"
done
for applet in init halt poweroff reboot; do ln -s ../bin/busybox "$stage/sbin/$applet"; done
install -m 755 "$root/rootfs/init" "$stage/init"
install -m 644 "$root/rootfs/etc/"* "$stage/etc/"
chmod 1777 "$stage/tmp"
mknod -m 600 "$stage/dev/console" c 5 1
mknod -m 666 "$stage/dev/null" c 1 3
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$stage"
    find . -print0 | sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9
) > "$root/out/images/initramfs.cpio.gz.new"
gzip -t "$root/out/images/initramfs.cpio.gz.new"
mv "$root/out/images/initramfs.cpio.gz.new" "$root/out/images/initramfs.cpio.gz"
