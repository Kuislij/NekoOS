#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    echo 'Usage: bash os check' >&2
    exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$root/scripts/bootstrap-dev.sh"
mkdir -p "$root/build/logs"
exec > >(tee "$root/build/logs/check-dev.log") 2>&1
echo 'Checking host toolchain and diskless QEMU startup (milestone 1).'
for pass in 1 2; do
    printf '\nPass %s/2\n' "$pass"
    bash "$root/scripts/check-toolchain.sh"
    bash "$root/scripts/check-qemu.sh"
done
echo 'DEV_ENV_READY'
