#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
[[ -n "${FAKEROOTKEY:-}" ]] || die 'Internal command: invoke through bash os build.'
[[ $# == 1 && -f "$1" ]] || die 'Expected a built BusyBox binary.'
stage="$root/build/rootfs"
# Exact generated path under the verified build directory; never accept a caller path.
rm -rf -- "$stage"
mkdir -p "$stage"/{dev/pts,etc/neko/services,home,media,mnt,opt,proc,root,run/lock,state,sys,tmp,usr/bin,usr/include,usr/lib,usr/lib64,usr/local/bin,usr/local/etc/neko/services,usr/local/lib,usr/local/sbin,usr/sbin,usr/share/nekoos/examples,usr/share/nekoos/packages,usr/share/udhcpc,var/cache,var/lib/neko-services/enabled,var/lib/neko-services/disabled,var/log,var/tmp}
# One copy of each program lives under /usr. Classic paths remain available.
ln -s usr/bin "$stage/bin"
ln -s usr/sbin "$stage/sbin"
ln -s usr/lib "$stage/lib"
ln -s usr/lib64 "$stage/lib64"
ln -s ../run "$stage/var/run"
ln -s ../run/lock "$stage/var/lock"
install -m 755 "$1" "$stage/usr/bin/busybox"
toolchain="$root/build/toolchain-root"
[[ -x "$toolchain/usr/bin/tcc" ]] || die 'C toolchain is missing.'
cp -a "$toolchain/usr/include/." "$stage/usr/include/"
cp -a "$toolchain/usr/lib/." "$stage/usr/lib/"
cp -a "$toolchain/lib/ld-musl-x86_64.so.1" "$stage/usr/lib/ld-musl-x86_64.so.1"
install -m 755 "$toolchain/usr/bin/tcc" "$stage/usr/bin/tcc"
ln -s tcc "$stage/usr/bin/cc"
"$1" --list > "$root/build/busybox-applets.txt"
while IFS= read -r applet; do
    [[ "$applet" == busybox ]] || ln -s busybox "$stage/usr/bin/$applet"
done < "$root/build/busybox-applets.txt"
for applet in sh mount mkdir sleep ifconfig route udhcpc ping wget tar sha256sum flock readlink; do
    [[ -x "$stage/usr/bin/$applet" ]] || die "Missing required applet: $applet"
done
for applet in init halt poweroff reboot; do
    ln -s ../bin/busybox "$stage/usr/sbin/$applet"
done
install -m 755 "$root/rootfs/usr/bin/neko-help" "$stage/usr/bin/neko-help"
install -m 755 "$root/rootfs/usr/bin/neko-shell" "$stage/usr/bin/neko-shell"
install -m 755 "$root/rootfs/usr/bin/neko-boot-status" "$stage/usr/bin/neko-boot-status"
install -m 755 "$root/rootfs/usr/bin/neko-net-status" "$stage/usr/bin/neko-net-status"
install -m 755 "$root/rootfs/usr/bin/neko-service" "$stage/usr/bin/neko-service"
install -m 755 "$root/rootfs/usr/bin/neko-pkg" "$stage/usr/bin/neko-pkg"
install -m 755 "$root/rootfs/usr/share/udhcpc/default.script" "$stage/usr/share/udhcpc/default.script"
install -m 644 "$root/rootfs/usr/share/nekoos/examples/hello.c" \
    "$stage/usr/share/nekoos/examples/hello.c"
python3 "$root/tools/make_package.py" --format 1 --name neko-greet --version 0.1.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.1.0.npkg"
python3 "$root/tools/make_package.py" --name neko-greet --version 0.2.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet-v2.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.2.0.npkg"
python3 "$root/tools/make_package.py" --name neko-greet --version 0.3.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet-v3.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.3.0.npkg"
python3 "$root/tools/make_package.py" --name neko-companion --version 1.0.0 \
    --license NOASSERTION --depends 'neko-greet>=0.2.0' \
    --file "$root/packages/examples/neko-companion.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-companion-1.0.0.npkg"
for archive in "$root"/packages/local/*.npkg; do
    [[ -e "$archive" || -L "$archive" ]] || continue
    [[ -f "$archive" && ! -L "$archive" ]] || die "Local package must be a regular file: $archive"
    filename="${archive##*/}"
    [[ "$filename" =~ ^[a-z0-9][a-z0-9.+-]*\.npkg$ ]] || die "Invalid local package filename: $filename"
    [[ ! -e "$stage/usr/share/nekoos/packages/$filename" ]] || die "Duplicate package filename: $filename"
    (( $(stat -c%s "$archive") <= 17825792 )) || die "Local package is too large: $filename"
    install -m 644 "$archive" "$stage/usr/share/nekoos/packages/$filename"
done
install -m 755 "$root/rootfs/init" "$stage/init"
install -m 755 "$root/rootfs/neko-update-init" "$stage/neko-update"
install -m 644 "$root/rootfs/etc/"{group,hosts,inittab,os-release,passwd,profile} "$stage/etc/"
install -m 644 "$root/rootfs/etc/neko/boot-services" "$stage/etc/neko/boot-services"
install -m 755 "$root/rootfs/etc/neko/services/network" "$stage/etc/neko/services/network"
(
    cd "$stage"
    find etc -type f -print0 | sort -z | xargs -0 sha256sum
) > "$stage/usr/share/nekoos/etc-baseline.sha256"
chmod 1777 "$stage/tmp"
chmod 1777 "$stage/var/tmp"
chmod 700 "$stage/root"
mknod -m 600 "$stage/dev/console" c 5 1
mknod -m 666 "$stage/dev/null" c 1 3
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$stage"
    find . -print0 | sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9
) > "$root/out/images/initramfs.cpio.gz.new"
gzip -t "$root/out/images/initramfs.cpio.gz.new"
mv "$root/out/images/initramfs.cpio.gz.new" "$root/out/images/initramfs.cpio.gz"
python3 "$root/tools/validate_image.py" "$root/out/images/initramfs.cpio.gz"
# The maintenance entry point is needed only in the RAM image.
rm -- "$stage/neko-update"

# A small first-stage image mounts the writable system disk and switch_roots.
bootstrap="$root/build/bootstrap-rootfs"
[[ ! -L "$bootstrap" ]] || die 'Bootstrap staging directory must not be a symlink.'
rm -rf -- "$bootstrap"
mkdir -p "$bootstrap"/{bin,dev,proc,sys,sysroot}
install -m 755 "$1" "$bootstrap/bin/busybox"
ln -s busybox "$bootstrap/bin/sh"
install -m 755 "$root/rootfs/early-init" "$bootstrap/init"
mknod -m 600 "$bootstrap/dev/console" c 5 1
mknod -m 666 "$bootstrap/dev/null" c 1 3
find "$bootstrap" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$bootstrap"
    find . -print0 | sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9
) > "$root/out/images/bootstrap.cpio.gz.new"
gzip -t "$root/out/images/bootstrap.cpio.gz.new"
mv "$root/out/images/bootstrap.cpio.gz.new" "$root/out/images/bootstrap.cpio.gz"

# Build a template under the same fakeroot process as the staged rootfs so
# its ownership, permissions and device entries survive into ext4.
template="$root/out/images/system-template.img"
[[ ! -L "$template" && ! -L "$template.new" ]] || die 'System image output must not be a symlink.'
rm -f -- "$template.new"
qemu-img create -f raw "$template.new" 256M
E2FSPROGS_FAKE_TIME="$SOURCE_DATE_EPOCH" mke2fs -t ext4 -F -q -m 0 \
    -L NEKO_SYSTEM -U 4e454b4f-4f53-4000-8000-000000000001 \
    -d "$stage" "$template.new"
[[ "$(blkid -p -s TYPE -o value "$template.new")" == ext4 ]] || die 'System template is not ext4.'
mv "$template.new" "$template"
echo "SYSTEM_TEMPLATE_READY: $template"
