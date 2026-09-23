#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    echo 'Usage: bash scripts/check-qemu.sh' >&2
    exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$root/scripts/bootstrap-dev.sh"
mkdir -p "$root/build/logs"
exec > >(tee "$root/build/logs/qemu-check.log") 2>&1
qemu-system-x86_64 --version
# Start a paused, diskless machine and request clean exit via the monitor.
# TCG does not require nested KVM. Timeout prevents a hung check.
printf 'quit\n' | timeout 15s qemu-system-x86_64 \
    -machine q35 -accel tcg -m 128M -smp 1 -S \
    -nodefaults -display none -serial none -monitor stdio -nic none
echo 'QEMU_CHECK_PASSED (startup only; no guest OS boot yet)'
