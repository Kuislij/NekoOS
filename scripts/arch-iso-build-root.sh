#!/usr/bin/env bash
# Build with the signed Arch bootstrap inside a private mount namespace.
set -euo pipefail
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $# == 3 || ($# == 4 && "$4" == --private-namespace) ]] || die 'Internal ISO helper usage.'
(( EUID == 0 )) || die 'ISO helper requires root.'
root="$(realpath -e -- "$1")"
script_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ "$root" == "$script_root" && "$root" != / && "$root" != /mnt/* ]] || die 'Unsafe repository.'
[[ "$2" =~ ^[1-9][0-9]*$ && "$3" =~ ^[0-9]+$ ]] || die 'Invalid output owner.'
owner="$2:$3"
if [[ $# == 3 ]]; then
    exec unshare --mount --propagation private -- bash "$root/scripts/arch-iso-build-root.sh" \
        "$root" "$2" "$3" --private-namespace
fi
[[ "$(readlink /proc/self/ns/mnt)" != "$(readlink /proc/1/ns/mnt)" ]] || die 'Missing private mount namespace.'
source "$root/arch/sources.sh"
export LC_ALL=C TZ=UTC SYSTEMD_OFFLINE=1
export SOURCE_DATE_EPOCH=1790812800
umask 022
for directory in build build/arch build/archiso cache cache/arch cache/arch/packages out out/arch; do
    [[ ! -L "$root/$directory" ]] || die "Unsafe directory: $directory"
    mkdir -p "$root/$directory"
done
chown "$owner" "$root/build/archiso"
# Shared package cache must not race the disk builder; test/user disks are never attached here.
[[ ! -L "$root/build/arch/.build.lock" ]] || die 'Unsafe build lock.'
exec 9>>"$root/build/arch/.build.lock"
flock -n 9 || die 'Another Arch build or VM is using the build inputs.'
[[ ! -L "$root/out/arch/iso" ]] || die 'Unsafe ISO output directory.'
available=$(df --output=avail -B1 "$root/build/archiso" | tail -n 1)
(( available >= 12 * 1024 * 1024 * 1024 )) || die 'At least 12 GiB of free Linux filesystem space is required.'
bootstrap="$root/cache/arch/bootstrap-$ARCH_BOOTSTRAP_VERSION.tar.zst"
[[ -f "$bootstrap" && ! -L "$bootstrap" ]] || die 'Missing verified bootstrap.'
printf '%s  %s\n' "$ARCH_BOOTSTRAP_SHA256" "$bootstrap" | sha256sum -c -
runner="$(mktemp -d "$root/build/archiso/runner.XXXXXXXX")"
output="$(mktemp -d "$root/out/arch/.iso-new.XXXXXXXX")"
previous=''
mounted() { findmnt -rn -o TARGET | awk -v p="$runner" '$0==p || index($0,p"/")==1 {f=1} END {exit !f}'; }
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    chroot "$runner" /usr/bin/gpgconf --homedir /etc/pacman.d/gnupg --kill all >/dev/null 2>&1
    for attempt in {1..40}; do
        mounted || break
        umount -R -- "$runner" 2>/dev/null && break
        sleep 0.25
    done
    if ! mounted; then rm -rf -- "$runner"; else echo "Build mounts retained for inspection: $runner" >&2; fi
    if [[ -n "$previous" && -d "$previous" && ! -e "$root/out/arch/iso" ]]; then
        mv -T -- "$previous" "$root/out/arch/iso"
    fi
    [[ ! -d "$output" ]] || rm -rf -- "$output"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
tar --zstd --numeric-owner --same-owner --strip-components=1 -xpf "$bootstrap" -C "$runner"
rm -f -- "$runner/etc/resolv.conf"
cp -L -- /etc/resolv.conf "$runner/etc/resolv.conf"
cat > "$runner/etc/pacman.conf" <<EOF
[options]
Architecture = auto
CheckSpace
SigLevel = Required TrustedOnly DatabaseOptional
LocalFileSigLevel = Required
[core]
Server = $ARCH_REPOSITORY_URL/\$repo/os/\$arch
[extra]
Server = $ARCH_REPOSITORY_URL/\$repo/os/\$arch
EOF
mount --bind "$runner" "$runner"
mount --make-private "$runner"
mount -t proc -o nosuid,noexec,nodev proc "$runner/proc"
mount -t sysfs -o nosuid,noexec,nodev,ro sysfs "$runner/sys"
mount --rbind /dev "$runner/dev"
mount --make-rslave "$runner/dev"
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs "$runner/run"
mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs "$runner/tmp"
mount --bind "$root/cache/arch/packages" "$runner/var/cache/pacman/pkg"
chroot "$runner" /usr/bin/pacman-key --init
chroot "$runner" /usr/bin/pacman-key --populate archlinux
chroot "$runner" /usr/bin/pacman -Syyu --needed --noconfirm archiso rsync python
chroot "$runner" /usr/bin/pacman -Q archiso > "$output/archiso-version.txt"
[[ "$(cat "$output/archiso-version.txt")" == 'archiso 90-1' ]] || die 'Unexpected archiso version in pinned snapshot.'
profile="$runner/profile"
mkdir -p "$profile"
# Reuse only upstream boot/initramfs templates, without releng's root login or network services.
for directory in syslinux efiboot; do cp -a -- "$runner/usr/share/archiso/configs/baseline/$directory" "$profile/"; done
mkdir -p "$profile/airootfs/etc/mkinitcpio.conf.d" "$profile/airootfs/etc/mkinitcpio.d"
cp -a -- "$runner/usr/share/archiso/configs/releng/airootfs/etc/mkinitcpio.conf.d/archiso.conf" "$profile/airootfs/etc/mkinitcpio.conf.d/"
cp -a -- "$runner/usr/share/archiso/configs/releng/airootfs/etc/mkinitcpio.d/linux.preset" "$profile/airootfs/etc/mkinitcpio.d/"
sed -i -e 's/^COMPRESSION=.*/COMPRESSION="zstd"/' -e 's/^COMPRESSION_OPTIONS=.*/COMPRESSION_OPTIONS=(-T2 -3)/' \
    "$profile/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
rsync -aH --chown=0:0 --chmod=D755,F644 -- "$root/arch/airootfs/" "$profile/airootfs/"
rsync -aH --chown=0:0 --chmod=D755,F644 -- "$root/live/airootfs/" "$profile/airootfs/"
attribution="$profile/airootfs/usr/share/licenses/nekoos-archiso-templates"
install -d -m 0755 "$attribution"
install -m 0644 "$runner/usr/share/doc/archiso/AUTHORS.rst" "$attribution/AUTHORS.rst"
install -m 0644 "$runner/usr/share/licenses/spdx/GPL-3.0-or-later.txt" "$attribution/LICENSE"
install -m 0644 "$root/live/UPSTREAM.md" "$attribution/UPSTREAM.md"
cp -- "$root/live/profiledef.sh" "$profile/profiledef.sh"
cp -- "$runner/etc/pacman.conf" "$profile/pacman.conf"
cat "$root/arch/packages.x86_64" "$root/live/packages.x86_64" > "$profile/packages.x86_64"
# Set boot timeout/serial console in copied templates; keep upstream licensing and structure.
find "$profile/syslinux" "$profile/efiboot" -type f \( -name '*.cfg' -o -name '*.conf' \) -print0 |
    xargs -0 sed -i -e 's/Arch Linux install medium/NekoOS Live/g' -e 's/Arch Linux/NekoOS Live/g' \
        -e 's/console=tty1/console=tty0 console=ttyS0,115200/g' \
        -e 's/archisosearchuuid=%ARCHISO_UUID%/& console=tty0 console=ttyS0,115200 systemd.show_status=false cow_spacesize=50%/g' \
        -e 's/^TIMEOUT .*/TIMEOUT 20/' -e 's/^timeout .*/timeout 2/'
profile_sha=$( { cd "$root"; find live arch/airootfs -type f -print0 | sort -z | xargs -0 sha256sum; sha256sum arch/packages.x86_64 scripts/arch-iso-build-root.sh arch/sources.sh; } | sha256sum | cut -d' ' -f1)
chroot "$runner" /usr/bin/mkarchiso -v -w /work -o /result /profile
mapfile -t generated < <(find "$runner/result" -maxdepth 1 -type f -name '*.iso')
[[ ${#generated[@]} == 1 ]] || die 'Expected exactly one built ISO.'
mv -- "${generated[0]}" "$output/nekoos-live-x86_64.iso"
cp -- "$runner/work/iso/neko/pkglist.x86_64.txt" "$output/packages.lock"
git_commit=$(git -c safe.directory="$root" -C "$root" rev-parse HEAD)
git_dirty=$(git -c safe.directory="$root" -C "$root" status --porcelain --untracked-files=normal | wc -l)
python3 - "$output/build-info.json" "$ARCH_REPOSITORY_SNAPSHOT" "$profile_sha" "$git_commit" "$git_dirty" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'format': 1, 'snapshot': sys.argv[2], 'profile_sha256': sys.argv[3],
    'git_commit': sys.argv[4], 'source_dirty': int(sys.argv[5]) != 0, 'archiso': '90-1',
    'source_date_epoch': 1790812800, 'live_persistence': False, 'secure_boot': False}, indent=2) + '\n')
PY
printf 'bios-cd\nuefi-cd\nbios-usb\nuefi-usb\n' > "$output/boot-modes.txt"
(cd "$output" && sha256sum nekoos-live-x86_64.iso packages.lock build-info.json archiso-version.txt boot-modes.txt > SHA256SUMS)
chmod 0755 "$output"
chmod 0644 "$output"/*
chown "$owner" "$output" "$output"/*
if [[ -e "$root/out/arch/iso" ]]; then
    [[ -d "$root/out/arch/iso" ]] || die 'ISO output is not a directory.'
    previous="$(mktemp -d "$root/out/arch/.iso-previous.XXXXXXXX")"
    rmdir "$previous"
    mv -T -- "$root/out/arch/iso" "$previous"
fi
mv -T -- "$output" "$root/out/arch/iso"
output=''
[[ -z "$previous" ]] || rm -rf -- "$previous"
previous=''
echo 'ARCHISO_BUILD_PASSED'
