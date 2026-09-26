#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
quiet='quiet loglevel=4'
mode=disk
boot=direct
network=off
system=off
graphics=off
for option in "$@"; do
    case "$option" in
        --verbose) quiet='' ;;
        --ram) mode=ram ;;
        --iso) boot=iso ;;
        --net) network=on ;;
        --system) system=on ;;
        --graphics) graphics=on ;;
        *) die 'Usage: bash os run [--ram] [--iso] [--system] [--net] [--graphics] [--verbose]' ;;
    esac
done
[[ "$boot" != iso || "$mode" != ram ]] || die 'ISO boot currently requires the persistent virtual disk.'
[[ "$system" != on || "$mode" == disk ]] || die '--system requires a virtual disk.'
mkdir -p "$root/build/logs"
echo 'Сборка NekoOS; подробный вывод: build/logs/build.log'
if ! bash "$root/scripts/build.sh" > "$root/build/logs/run-build.log" 2>&1; then
    tail -n 35 "$root/build/logs/run-build.log" >&2
    die 'Сборка не удалась. Полный вывод: build/logs/build.log'
fi
drive_args=()
net_args=(-nic none)
if [[ "$network" == on ]]; then
    net_args=(-nic user,model=virtio-net-pci,ipv6=off)
    echo 'Виртуальная сеть включена: DHCP и исходящие подключения через QEMU.'
fi
boot_args=(-kernel "$root/out/images/bzImage" -initrd "$root/out/images/initramfs.cpio.gz")
append="console=ttyS0,115200 rdinit=/init panic=-1 $quiet"
display_args=(-display none)
memory=256M
if [[ "$graphics" == on ]]; then
    display_args=(-display gtk -device virtio-vga -device virtio-keyboard-pci -device virtio-mouse-pci)
    memory=512M
    # Keep the serial device last: /dev/console and the shell stay on ttyS0.
    append="console=tty0 $append"
    echo 'Открываю графическое окно QEMU. Текстовая консоль остаётся в этом терминале.'
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
