#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash os build'
bash "$root/scripts/bootstrap-dev.sh"
exec 9>"$root/build/.lock"
flock -n 9 || die 'Another build is running.'
mkdir -p "$root/build/logs" "$root/cache/sources" "$root/build/sources" "$root/out/images"
exec > >(tee "$root/build/logs/build.log") 2>&1
jobs="${JOBS:-4}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer.'
export KBUILD_BUILD_USER=neko KBUILD_BUILD_HOST=builder KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="$(date -u -d "@$SOURCE_DATE_EPOCH" '+%Y-%m-%d %H:%M:%S UTC')"

fetch() {
    local url="$1" hash="$2" archive="$root/cache/sources/${1##*/}"
    if [[ ! -f "$archive" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --connect-timeout 30 -o "$archive.part" "$url"
        printf '%s  %s\n' "$hash" "$archive.part" | sha256sum -c -
        mv -- "$archive.part" "$archive"
    fi
    printf '%s  %s\n' "$hash" "$archive" | sha256sum -c -
}
extract() {
    local archive="$1" name="$2"
    if [[ ! -f "$root/build/sources/$name/.neko-extracted" ]]; then
        [[ ! -L "$root/build/sources" ]] || die 'Source directory must not be a symlink.'
        rm -rf -- "$root/build/sources/$name"
        tar --no-same-owner -xf "$archive" -C "$root/build/sources"
        touch "$root/build/sources/$name/.neko-extracted"
    fi
}
fetch "$LINUX_URL" "$LINUX_SHA256"
fetch "$BUSYBOX_URL" "$BUSYBOX_SHA256"
bash "$root/scripts/verify-kernel.sh"
extract "$root/cache/sources/${LINUX_URL##*/}" "linux-$LINUX_VERSION"
extract "$root/cache/sources/${BUSYBOX_URL##*/}" "busybox-$BUSYBOX_VERSION"
kernel="$root/build/sources/linux-$LINUX_VERSION"
busybox="$root/build/sources/busybox-$BUSYBOX_VERSION"
kout="$root/build/linux-$LINUX_VERSION"
bout="$root/build/busybox-$BUSYBOX_VERSION"
[[ ! -L "$kout" && ! -L "$bout" ]] || die 'Component build directories must not be symlinks.'
mkdir -p "$kout" "$bout"
make -C "$kernel" O="$kout" ARCH=x86_64 \
    KCONFIG_ALLCONFIG="$root/kernel/configs/x86_64.config" allnoconfig
make -C "$kernel" O="$kout" ARCH=x86_64 -j"$jobs" bzImage
make -C "$busybox" O="$bout" allnoconfig
# BusyBox's older Kconfig resets booleans during allnoconfig. Apply our
# selection afterward, then accept defaults only for newly enabled dependencies.
while IFS= read -r option; do
    [[ "$option" == CONFIG_*=* ]] || continue
    key="${option%%=*}"
    sed -i -e "/^${key}=/d" -e "/^# ${key} is not set$/d" "$bout/.config"
    printf '%s\n' "$option" >> "$bout/.config"
done < "$root/configs/busybox.config"
make -C "$busybox" O="$bout" oldconfig < <(yes '')
make -C "$busybox" O="$bout" -j"$jobs"
if readelf -l "$bout/busybox" | grep -q INTERP; then die 'BusyBox must be statically linked.'; fi
fakeroot bash "$root/scripts/image.sh" "$bout/busybox"
install -m 644 "$kout/arch/x86/boot/bzImage" "$root/out/images/bzImage.new"
mv "$root/out/images/bzImage.new" "$root/out/images/bzImage"
cp "$kout/.config" "$root/out/images/kernel.config"
cp "$bout/.config" "$root/out/images/busybox.config"
(cd "$root/out/images"; sha256sum bzImage initramfs.cpio.gz > SHA256SUMS)
echo 'BUILD_READY: out/images/bzImage and initramfs.cpio.gz'
