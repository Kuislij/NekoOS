#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
case "${1:-}" in
    '') quiet='quiet loglevel=4' ;;
    --verbose) quiet='' ;;
    *) die 'Usage: bash os run [--verbose]' ;;
esac
(( $# <= 1 )) || die 'Usage: bash os run [--verbose]'
mkdir -p "$root/build/logs"
echo 'Сборка NekoOS; подробный вывод: build/logs/build.log'
if ! bash "$root/scripts/build.sh" > "$root/build/logs/run-build.log" 2>&1; then
    tail -n 35 "$root/build/logs/run-build.log" >&2
    die 'Сборка не удалась. Полный вывод: build/logs/build.log'
fi
echo 'Запускаю NekoOS. Когда появится neko#, введите neko-help.'
echo 'Выход: Ctrl+A, затем X. Файлы внутри гостя живут до выключения.'
exec qemu-system-x86_64 -machine q35 -accel tcg -cpu qemu64 -m 256M -smp 1 \
    -nodefaults -display none -monitor none -nic none -no-reboot \
    -chardev stdio,id=console,mux=on,signal=off,logfile="$root/build/logs/serial.log" \
    -serial chardev:console \
    -kernel "$root/out/images/bzImage" -initrd "$root/out/images/initramfs.cpio.gz" \
    -append "console=ttyS0,115200 rdinit=/init panic=-1 $quiet"
