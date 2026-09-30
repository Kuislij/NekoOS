#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
quiet='quiet loglevel=4'
mode=disk
boot=direct
network=off
system=off
graphics=off
x11=off
no_build=off
for option in "$@"; do
    case "$option" in
        --verbose) quiet='' ;;
        --ram) mode=ram ;;
        --iso) boot=iso ;;
        --net) network=on ;;
        --system) system=on ;;
        --graphics) graphics=on ;;
        --x11) graphics=on; x11=on ;;
        --no-build) no_build=on ;;
        *) die 'Usage: bash os run [--no-build] [--ram] [--iso] [--system] [--net] [--graphics|--x11] [--verbose]' ;;
    esac
done
[[ "$boot" != iso || "$mode" != ram ]] || die 'ISO boot currently requires the persistent virtual disk.'
[[ "$system" != on || "$mode" == disk ]] || die '--system requires a virtual disk.'
[[ "$x11" != on || "$boot" != iso ]] || die '--x11 is not yet available with --iso.'
mkdir -p "$root/build/logs"
if [[ "$no_build" != on ]]; then
    echo 'Сборка NekoOS; подробный вывод: build/logs/build.log'
    if ! bash "$root/scripts/build.sh" > "$root/build/logs/run-build.log" 2>&1; then
        tail -n 35 "$root/build/logs/run-build.log" >&2
        die 'Сборка не удалась. Полный вывод: build/logs/build.log'
    fi
fi

# Keep build outputs stable from verification through the lifetime of QEMU.
# The builder takes the exclusive version of this same lock.
[[ ! -L "$root/build/.lock" && (! -e "$root/build/.lock" || -f "$root/build/.lock") ]] ||
    die 'Build lock must be a regular file, not a symlink.'
exec 9>>"$root/build/.lock"
flock -s -n 9 || die 'Another build is changing the images. Wait for it to finish before running NekoOS.'

# A cached image must pass the same checksum and rootfs validation as boot tests.
# Check every manifest path before sha256sum follows it, require checksums for
# selected boot inputs, and reject paths outside the four build outputs.
images="$root/out/images"
required_images=(bzImage initramfs.cpio.gz)
if [[ "$system" == on || "$boot" == iso ]]; then
    required_images+=(bootstrap.cpio.gz)
fi
if [[ "$system" == on ]]; then
    required_images+=(system-template.img)
fi
for file in SHA256SUMS "${required_images[@]}"; do
    [[ -f "$images/$file" && ! -L "$images/$file" ]] ||
        die "Missing or unsafe image: $file. Run bash os build."
done
declare -A manifest_files=()
while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ "$entry" =~ ^[0-9a-f]{64}\ \ (bzImage|initramfs[.]cpio[.]gz|bootstrap[.]cpio[.]gz|system-template[.]img)$ ]] ||
        die 'Image checksum manifest contains a malformed or unsafe entry. Run bash os build.'
    file="${BASH_REMATCH[1]}"
    [[ -z "${manifest_files[$file]+present}" ]] ||
        die "Image checksum manifest repeats $file. Run bash os build."
    [[ -f "$images/$file" && ! -L "$images/$file" ]] ||
        die "Missing or unsafe checksummed image: $file. Run bash os build."
    manifest_files[$file]=present
done < "$images/SHA256SUMS"
for file in "${required_images[@]}"; do
    [[ -n "${manifest_files[$file]+present}" ]] ||
        die "Image checksum is missing for $file. Run bash os build."
done
echo 'Проверяю контрольные суммы и содержимое готового образа NekoOS.'
(cd "$images" && sha256sum --strict --check SHA256SUMS >/dev/null) ||
    die 'Image checksum verification failed; refusing to boot. Run bash os build.'
python3 "$root/tools/validate_image.py" "$images/initramfs.cpio.gz" >/dev/null ||
    die 'Image contents failed validation; refusing to boot. Run bash os build.'
drive_args=()
net_args=(-nic none)
if [[ "$network" == on ]]; then
    net_args=(-nic user,model=virtio-net-pci,ipv6=off)
    echo 'Виртуальная сеть включена: DHCP и исходящие подключения через QEMU.'
fi
boot_args=(-kernel "$root/out/images/bzImage" -initrd "$root/out/images/initramfs.cpio.gz")
append="console=ttyS0,115200 rdinit=/init panic=-1 $quiet"
display_args=(-display none)
memory=512M
if [[ "$graphics" == on ]]; then
    display_args=(-display gtk -device virtio-vga -device virtio-keyboard-pci -device virtio-tablet-pci)
    # Kernel messages stay on serial instead of drawing over the desktop.
    echo 'Открываю графический экран NekoOS в QEMU. Текстовая консоль остаётся в этом терминале.'
fi
if [[ "$x11" == on ]]; then
    append="$append neko.x11=1"
    echo 'Запускаю отдельный X11-сеанс с оконным менеджером evilwm.'
fi
if [[ "$mode" == disk ]]; then
    bash "$root/scripts/create-disk.sh"
    exec 8>"$root/out/disks/.run-lock"
    flock -n 8 || die 'This NekoOS virtual disk is already in use.'
    drive_args=(-drive "file=$root/out/disks/state.img,format=raw,if=virtio")
    append="$append neko.state=required"
    echo 'Запускаю NekoOS с сохранением файлов в /root и /home.'
else
    echo 'Запускаю временную NekoOS: изменения исчезнут после выключения.'
fi
if [[ "$system" == on ]]; then
    bash "$root/scripts/create-system-disk.sh"
    drive_args=(-drive "file=$root/out/disks/system.img,format=raw,if=virtio"
                -drive "file=$root/out/disks/state.img,format=raw,if=virtio")
    boot_args=(-kernel "$root/out/images/bzImage" -initrd "$root/out/images/bootstrap.cpio.gz")
    append="$append neko.system=required"
    echo 'Системный раздел на отдельном виртуальном диске; /etc и /usr сохраняются.'
fi
if [[ "$boot" == iso ]]; then
    iso_args=()
    iso_name=NekoOS.iso
    if [[ "$system" == on ]]; then
        iso_args=(--system)
        iso_name=NekoOS-system.iso
    fi
    bash "$root/scripts/create-iso.sh" "${iso_args[@]}" > "$root/build/logs/iso.log" 2>&1 || {
        tail -n 35 "$root/build/logs/iso.log" >&2
        die 'Could not create bootable ISO. See build/logs/iso.log.'
    }
    boot_args=(-drive "file=$root/out/images/$iso_name,media=cdrom,if=ide" -boot order=d)
    echo "Запуск через виртуальный BIOS и GRUB (образ out/images/$iso_name)."
else
    boot_args+=(-append "$append")
fi
echo 'Когда появится neko#, введите neko-help. Выход: Ctrl+A, затем X.'
exec qemu-system-x86_64 -machine q35 -accel tcg -cpu qemu64 -m "$memory" -smp 2 \
    -nodefaults "${display_args[@]}" -monitor none "${net_args[@]}" -no-reboot \
    "${drive_args[@]}" \
    -chardev stdio,id=console,mux=on,signal=off,logfile="$root/build/logs/serial.log" \
    -serial chardev:console \
    "${boot_args[@]}"
