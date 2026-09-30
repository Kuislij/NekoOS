#!/usr/bin/env bash
# Root is confined to a private mount namespace and named Arch build outputs.
set -euo pipefail
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 || ($# == 4 && "${4:-}" == --private-namespace) ]] ||
    die 'Internal usage: arch-build-root.sh REPOSITORY UID GID'
(( EUID == 0 )) || die 'The image helper requires root privileges.'
root="$(realpath -e -- "$1")"
script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ "$root" == "$script_root" && "$root" != / && "$root" != /mnt/* &&
   "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'Unsafe image repository.'
owner_uid="$2"
owner_gid="$3"
[[ "$owner_uid" =~ ^[1-9][0-9]*$ && "$owner_gid" =~ ^[0-9]+$ ]] || die 'Invalid output owner.'
if [[ $# == 3 ]]; then
    exec unshare --mount --propagation private -- \
        bash "$root/scripts/arch-build-root.sh" "$root" "$owner_uid" "$owner_gid" --private-namespace
fi
[[ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]] ||
    die 'The image helper must run in a private mount namespace.'
source "$root/arch/sources.sh"
export LC_ALL=C TZ=UTC SYSTEMD_OFFLINE=1
umask 022
for command in sha256sum tar zstd flock chroot mount umount findmnt mountpoint \
               sfdisk losetup mkfs.ext4 rsync blkid e2fsck truncate realpath; do
    command -v "$command" >/dev/null || die "Missing image build tool: $command"
done
for directory in build build/arch cache cache/arch cache/arch/packages out out/arch; do
    [[ ! -L "$root/$directory" ]] || die "Unsafe directory: $directory"
    mkdir -p "$root/$directory"
done
build="$root/build/arch"
outputs="$root/out/arch"
cache="$root/cache/arch"
safe_path() {
    [[ "$1" == "$build/"* || "$1" == "$outputs/"* ]] || die "Path outside Arch build/output directories: $1"
    [[ ! -L "$1" ]] || die "Unsafe symlink: $1"
}
lock="$build/.build.lock"
safe_path "$lock"
[[ ! -e "$lock" || -f "$lock" ]] || die 'Build lock is not a regular file.'
exec 9>>"$lock"
flock -n 9 || die 'An Arch build or running VM is already using these images.'
bootstrap="$cache/bootstrap-$ARCH_BOOTSTRAP_VERSION.tar.zst"
[[ -f "$bootstrap" && ! -L "$bootstrap" ]] || die 'Missing or unsafe verified Arch bootstrap.'
printf '%s  %s\n' "$ARCH_BOOTSTRAP_SHA256" "$bootstrap" | sha256sum -c -
[[ -f "$root/arch/packages.x86_64" && ! -L "$root/arch/packages.x86_64" ]] || die 'Missing Arch package list.'
profile_hash="$(
    cd "$root"
    { printf '%s\n%s\n' "$ARCH_BOOTSTRAP_SHA256" "$ARCH_REPOSITORY_SNAPSHOT";
      sha256sum scripts/arch-build-root.sh;
      find arch -type f -print0 | sort -z | xargs -0 sha256sum;
      find arch -type l -printf '%P -> %l\n' | sort; } | sha256sum | cut -d' ' -f1
)"
cached_root="$build/rootfs"
stamp="$build/rootfs.stamp"
safe_path "$cached_root"
safe_path "$stamp"
safe_path "$outputs/images"
[[ ! -e "$stamp" || -f "$stamp" ]] || die 'Rootfs stamp is not a regular file.'
temp_images="$(mktemp -d "$outputs/.images-new.XXXXXXXX")"
mount_dir="$(mktemp -d "$build/.disk-root.XXXXXXXX")"
new_root=''
stage=''
loop_device=''
image="$temp_images/system-template.img"
previous_images=''
previous_root=''
published=off

has_mounts() {
    findmnt -rn -o TARGET | awk -v prefix="$1" \
        '$0 == prefix || index($0, prefix "/") == 1 { found=1 } END { exit !found }'
}
verify_loop() {
    [[ "$loop_device" =~ ^/dev/loop[0-9]+$ && -b "$loop_device" && ! -L "$loop_device" ]] ||
        die 'Unexpected loop device.'
    local backing
    backing="$(losetup --noheadings --output BACK-FILE "$loop_device")"
    [[ "$(realpath -e -- "$backing")" == "$(realpath -e -- "$image")" ]] ||
        die 'Loop device does not back the generated Arch image.'
}
stop_guest_key_daemons() {
    local target="$1"
    if [[ -x "$target/usr/bin/gpgconf" ]]; then
        chroot "$target" /usr/bin/gpgconf --homedir /etc/pacman.d/gnupg --kill all >/dev/null 2>&1 || true
    fi
}
release_api() {
    local target="$1" attempt
    stop_guest_key_daemons "$target"
    # gpgconf requests shutdown asynchronously. Give only this chroot's
    # daemons time to release their files before unmounting its API mounts.
    for attempt in {1..40}; do
        has_mounts "$target" || return 0
        if umount -R -- "$target" 2>/dev/null; then return 0; fi
        sleep 0.25
    done
    printf 'ERROR: Timed out releasing build mounts: %s\n' "$target" >&2
    return 1
}
cleanup() {
    local result=$?
    trap - EXIT INT TERM
    set +e
    for target in "$mount_dir" "$stage"; do
        [[ -n "$target" ]] || continue
        if has_mounts "$target"; then
            release_api "$target"
        fi
    done
    if [[ -n "$loop_device" ]]; then
        # Never detach any loop other than the one still backing our temp image.
        local backing
        backing="$(losetup --noheadings --output BACK-FILE "$loop_device" 2>/dev/null)"
        if [[ "$backing" == "$image" ]]; then losetup --detach "$loop_device"; fi
    fi
    if [[ -n "$previous_images" && -d "$previous_images" && ! -e "$outputs/images" ]]; then
        mv -T -- "$previous_images" "$outputs/images"
    fi
    if [[ -n "$previous_root" && -d "$previous_root" && ! -e "$cached_root" ]]; then
        mv -T -- "$previous_root" "$cached_root"
    fi
    for target in "$mount_dir" "$new_root"; do
        [[ -n "$target" && -d "$target" && ! -L "$target" ]] || continue
        if ! has_mounts "$target"; then rm -rf -- "$target"; fi
    done
    if [[ "$published" != on && -d "$temp_images" && ! -L "$temp_images" ]]; then
        if ! losetup -j "$image" | grep -q .; then rm -rf -- "$temp_images"; fi
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mount_api() {
    local target="$1"
    mkdir -p "$target/proc" "$target/sys" "$target/dev" "$target/run" "$target/tmp"
    if ! mountpoint -q "$target"; then mount --bind "$target" "$target"; fi
    mount --make-private "$target"
    mount -t proc -o nosuid,noexec,nodev proc "$target/proc"
    mount -t sysfs -o nosuid,noexec,nodev,ro sysfs "$target/sys"
    mount --rbind /dev "$target/dev"
    mount --make-rslave "$target/dev"
    mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$target/run"
    mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$target/tmp"
}
if [[ -d "$cached_root" && -f "$stamp" && "$(cat "$stamp")" == "$profile_hash" ]]; then
    has_mounts "$cached_root" && die 'Cached rootfs has mounted filesystems; refusing to reuse it.'
    stage="$cached_root"
    echo 'ARCH_ROOTFS_REUSED: package/profile snapshot is unchanged'
else
    new_root="$(mktemp -d "$build/.rootfs-new.XXXXXXXX")"
    # The official tarball has a root.x86_64 prefix. Numeric ownership is required.
    tar --zstd --numeric-owner --same-owner --strip-components=1 -xpf "$bootstrap" -C "$new_root"
    stage="$new_root"
    mkdir -p "$stage/etc/pacman.d" "$stage/var/cache/pacman/pkg" "$stage/boot"
    # Do not follow an absolute guest symlink into the host when copying DNS.
    rm -f -- "$stage/etc/resolv.conf"
    cp -L -- /etc/resolv.conf "$stage/etc/resolv.conf"
    cat > "$stage/etc/pacman.conf" <<'EOF'
[options]
Architecture = auto
CheckSpace
SigLevel = Required TrustedOnly DatabaseOptional
LocalFileSigLevel = Required
[core]
Include = /etc/pacman.d/mirrorlist
[extra]
Include = /etc/pacman.d/mirrorlist
EOF
    printf 'Server = %s/$repo/os/$arch\n' "$ARCH_REPOSITORY_URL" > "$stage/etc/pacman.d/mirrorlist"
    mapfile -t packages < <(sed 's/#.*//; /^[[:space:]]*$/d' "$root/arch/packages.x86_64")
    for package in "${packages[@]}"; do
        [[ "$package" =~ ^[a-z0-9][a-z0-9+_.@-]*$ ]] || die "Invalid Arch package name: $package"
    done
    mount_api "$stage"
    mount --bind "$cache/packages" "$stage/var/cache/pacman/pkg"
    chroot "$stage" /usr/bin/pacman-key --init
    chroot "$stage" /usr/bin/pacman-key --populate archlinux
    chroot "$stage" /usr/bin/pacman -Syyu --noconfirm --needed \
        base linux base-devel grub efibootmgr dosfstools "${packages[@]}"
    # The profile is checked out by the ordinary host user. System files and
    # directories in the guest must belong to root, regardless of that UID.
    rsync -aH --chown=0:0 --chmod=D755,F644 -- "$root/arch/airootfs/" "$stage/"
    chmod 755 "$stage/usr/local/lib/nekoos/setup-desktop.sh"
    chroot "$stage" /usr/bin/bash /usr/local/lib/nekoos/setup-desktop.sh --development
    cat > "$stage/etc/mkinitcpio.conf" <<'EOF'
MODULES=(virtio_pci virtio_blk virtio_net virtio_gpu virtio_input usbhid xhci_pci ext4)
BINARIES=()
FILES=()
HOOKS=(base systemd modconf block filesystems keyboard fsck)
COMPRESSION="zstd"
EOF
    kernel_version=''
    for directory in "$stage"/usr/lib/modules/*; do
        if [[ -f "$directory/pkgbase" && "$(cat "$directory/pkgbase")" == linux ]]; then
            [[ -z "$kernel_version" ]] || die 'Multiple packaged linux kernel versions found.'
            kernel_version="${directory##*/}"
        fi
    done
    [[ -n "$kernel_version" && -f "$stage/usr/lib/modules/$kernel_version/vmlinuz" ]] ||
        die 'Packaged Arch linux kernel was not installed.'
    install -m 644 "$stage/usr/lib/modules/$kernel_version/vmlinuz" "$stage/boot/vmlinuz-linux"
    chroot "$stage" /usr/bin/mkinitcpio -k "$kernel_version" -g /boot/initramfs-linux.img --nopost
    # This pins the built image only. Installed guests use the ordinary rolling mirror.
    printf 'Server = %s/$repo/os/$arch\n' "$ARCH_RUNTIME_MIRROR" > "$stage/etc/pacman.d/mirrorlist"
    chroot "$stage" /usr/bin/pacman -Q > "$temp_images/packages.lock"
    release_api "$stage"
fi
if [[ ! -f "$temp_images/packages.lock" ]]; then
    chroot "$stage" /usr/bin/pacman -Q > "$temp_images/packages.lock"
fi
install -m 644 "$stage/boot/vmlinuz-linux" "$temp_images/vmlinuz-linux"
install -m 644 "$stage/boot/initramfs-linux.img" "$temp_images/initramfs-linux.img"
printf 'bootstrap=%s\nrepository_snapshot=%s\nprofile_sha256=%s\nruntime_mirror=%s\n' \
    "$ARCH_BOOTSTRAP_VERSION" "$ARCH_REPOSITORY_SNAPSHOT" "$profile_hash" "$ARCH_RUNTIME_MIRROR" \
    > "$temp_images/snapshot.txt"
truncate -s 12G "$image"
# Partition only the generated regular file, never a host block device.
[[ -f "$image" && ! -L "$image" ]] || die 'Unsafe generated disk image.'
sfdisk "$image" <<'EOF'
label: gpt
unit: sectors
start=2048, size=2048, type=21686148-6449-6E6F-744E-656564454649, name="NekoOS BIOS"
start=4096, size=524288, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="NekoOS EFI"
start=528384, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="NekoOS root"
EOF
if loop_device="$(losetup --find --show --partscan "$image")"; then
    verify_loop
    for count in {1..30}; do
        [[ -b "${loop_device}p2" && -b "${loop_device}p3" ]] && break
        sleep 0.1
    done
    if [[ ! -b "${loop_device}p2" || ! -b "${loop_device}p3" ]]; then
        verify_loop
        losetup --detach "$loop_device"
        loop_device=''
        echo 'WSL did not expose loop partitions; using explicit direct-boot fallback.' >&2
    fi
else
    loop_device=''
fi
if [[ -n "$loop_device" ]]; then
    for partition in "${loop_device}p2" "${loop_device}p3"; do
        [[ ! -L "$partition" && "$(basename "$(dirname "$(readlink -f "/sys/class/block/${partition##*/}")")")" == "${loop_device##*/}" ]] ||
            die 'Partition does not belong to the generated image loop device.'
    done
    verify_loop
    mkfs.ext4 -F -q -m 0 -L NEKO_ARCH_ROOT "${loop_device}p3"
    mount_api "$stage"
    verify_loop
    chroot "$stage" /usr/bin/mkfs.fat -F 32 -n NEKO_EFI "${loop_device}p2"
    release_api "$stage"
    mount "${loop_device}p3" "$mount_dir"
    rsync -aHAX --numeric-ids -- "$stage/" "$mount_dir/"
    mkdir -p "$mount_dir/boot/efi"
    mount "${loop_device}p2" "$mount_dir/boot/efi"
    root_uuid="$(blkid -p -s UUID -o value "${loop_device}p3")"
    efi_uuid="$(blkid -p -s UUID -o value "${loop_device}p2")"
    printf 'UUID=%s / ext4 defaults 0 1\nUUID=%s /boot/efi vfat umask=0077 0 2\n' \
        "$root_uuid" "$efi_uuid" > "$mount_dir/etc/fstab"
    printf '\nGRUB_DISABLE_OS_PROBER=true\n' >> "$mount_dir/etc/default/grub"
    mount_api "$mount_dir"
    verify_loop
    chroot "$mount_dir" /usr/bin/grub-install --target=i386-pc --recheck "$loop_device"
    verify_loop
    chroot "$mount_dir" /usr/bin/grub-install --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id=NekoOS --removable --no-nvram
    chroot "$mount_dir" /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg
    release_api "$mount_dir"
    e2fsck -f -n "${loop_device}p3"
    verify_loop
    losetup --detach "$loop_device"
    loop_device=''
    printf 'grub\n' > "$temp_images/boot-mode.txt"
else
    loop_device=''
    echo 'ARCH_DIRECT_BOOT_FALLBACK: loop devices unavailable; kernel/initramfs recovery boot required.' >&2
    # A mount-free fallback is explicit in metadata; it is not a GRUB-bootable disk.
    printf 'LABEL=NEKO_ARCH_ROOT / ext4 defaults 0 1\n' > "$stage/etc/fstab"
    truncate -s 0 "$image"
    truncate -s 12G "$image"
    mkfs.ext4 -F -q -m 0 -L NEKO_ARCH_ROOT -d "$stage" "$image"
    e2fsck -f -n "$image"
    printf 'direct\n' > "$temp_images/boot-mode.txt"
fi
has_mounts "$stage" && die 'Rootfs API mounts remain active; refusing to publish.'
has_mounts "$mount_dir" && die 'Disk mounts remain active; refusing to publish.'
(cd "$temp_images" && sha256sum vmlinuz-linux initramfs-linux.img system-template.img \
    packages.lock snapshot.txt boot-mode.txt > SHA256SUMS)
chmod 755 "$temp_images"
chmod 644 "$temp_images"/*
chown "$owner_uid:$owner_gid" "$temp_images" "$temp_images"/*

if [[ -n "$new_root" ]]; then
    if [[ -e "$cached_root" ]]; then
        [[ -d "$cached_root" && ! -L "$cached_root" ]] || die 'Unsafe cached rootfs.'
        has_mounts "$cached_root" && die 'Cached rootfs is mounted; refusing to replace it.'
        previous_root="$(mktemp -d "$build/.rootfs-previous.XXXXXXXX")"
        rmdir "$previous_root"
        mv -T -- "$cached_root" "$previous_root"
    fi
    mv -T -- "$new_root" "$cached_root"
    new_root=''
    stage="$cached_root"
    printf '%s\n' "$profile_hash" > "$stamp"
    if [[ -n "$previous_root" ]]; then rm -rf -- "$previous_root"; previous_root=''; fi
fi
if [[ -e "$outputs/images" ]]; then
    [[ -d "$outputs/images" && ! -L "$outputs/images" ]] || die 'Unsafe previous image directory.'
    previous_images="$(mktemp -d "$outputs/.images-previous.XXXXXXXX")"
    rmdir "$previous_images"
    mv -T -- "$outputs/images" "$previous_images"
fi
mv -T -- "$temp_images" "$outputs/images"
published=on
if [[ -n "$previous_images" ]]; then rm -rf -- "$previous_images"; previous_images=''; fi
echo "ARCH_IMAGES_READY: $outputs/images ($(cat "$outputs/images/boot-mode.txt"))"
