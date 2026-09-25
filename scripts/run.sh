#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
quiet='quiet loglevel=4'
mode=disk
for option in "$@"; do
    case "$option" in
        --verbose) quiet='' ;;
        --ram) mode=ram ;;
        *) die 'Usage: bash os run [--ram] [--verbose]' ;;
    esac
done
mkdir -p "$root/build/logs"
echo 'Сборка NekoOS; подробный вывод: build/logs/build.log'
if ! bash "$root/scripts/build.sh" > "$root/build/logs/run-build.log" 2>&1; then
    tail -n 35 "$root/build/logs/run-build.log" >&2
    die 'Сборка не удалась. Полный вывод: build/logs/build.log'
fi
drive_args=()
initrd_args=(-initrd "$root/out/images/initramfs.cpio.gz")
append="console=ttyS0,115200 rdinit=/init panic=-1 $quiet"
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
echo 'Когда появится neko#, введите neko-help. Выход: Ctrl+A, затем X.'
exec qemu-system-x86_64 -machine q35 -accel tcg -cpu qemu64 -m 256M -smp 1 \
    -nodefaults -display none -monitor none -nic none -no-reboot \
    "${drive_args[@]}" \
    -chardev stdio,id=console,mux=on,signal=off,logfile="$root/build/logs/serial.log" \
    -serial chardev:console \
    -kernel "$root/out/images/bzImage" "${initrd_args[@]}" \
    -append "$append"
