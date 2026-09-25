#!/usr/bin/env bash
set -euo pipefail
if (( $# > 1 )); then
    echo 'Usage: bootstrap-dev.sh [--install]' >&2
    exit 2
fi
if [[ "$(uname -s)" != Linux ]]; then
    echo 'Run this script inside Linux / WSL2.' >&2
    exit 1
fi
case "${1:-}" in
    '') ;;
    --install)
        source /etc/os-release
        case "$ID" in
            ubuntu|debian) ;;
            *) echo 'Automatic installation supports Ubuntu / Debian only.' >&2; exit 1 ;;
        esac
        elevate=()
        if (( EUID != 0 )); then elevate=(sudo); fi
        "${elevate[@]}" apt-get update
        "${elevate[@]}" apt-get install -y build-essential ninja-build git qemu-system-x86 \
            qemu-utils e2fsprogs grub-common grub-pc-bin xorriso \
            curl ca-certificates xz-utils bzip2 cpio fakeroot bc bison flex \
            libssl-dev libelf-dev python3 rsync gnupg
        ;;
    *) echo 'Usage: bootstrap-dev.sh [--install]' >&2; exit 2 ;;
esac
missing=0
for tool in gcc make ninja git qemu-system-x86_64 qemu-img mkfs.ext4 blkid \
    timeout tee curl xz bzip2 \
    cpio fakeroot bc bison flex python3 sha256sum gzip readelf flock gpg gpgv; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf '[OK] %s\n' "$tool"
    else
        printf '[MISSING] %s\n' "$tool" >&2
        missing=1
    fi
done
if (( missing )); then
    echo 'On Ubuntu/Debian: bash scripts/bootstrap-dev.sh --install' >&2
    exit 1
fi
echo 'Dependencies found. Run bash os check for functional checks.'
