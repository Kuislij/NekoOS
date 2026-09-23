#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Usage: bash os run'
bash "$root/scripts/build.sh"
echo 'Serial console: exit QEMU with Ctrl+A then X. Guest changes live in RAM.'
mkdir -p "$root/build/logs"
exec qemu-system-x86_64 -machine q35 -accel tcg -cpu qemu64 -m 256M -smp 1 \
    -nodefaults -display none -monitor none -nic none -no-reboot \
    -chardev stdio,id=console,mux=on,signal=off,logfile="$root/build/logs/serial.log" \
    -serial chardev:console \
    -kernel "$root/out/images/bzImage" -initrd "$root/out/images/initramfs.cpio.gz" \
    -append 'console=ttyS0,115200 rdinit=/init panic=-1'
