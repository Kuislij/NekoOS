#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$root/configs/sources.sh"
export LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH
umask 022
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || die 'Use x86_64 Linux / WSL2.'
# fakeroot reports UID 0 without granting real privileges.
if [[ -z "${FAKEROOTKEY:-}" ]]; then
    (( EUID != 0 )) || die 'Build and run as a regular user; root is only for host dependency installation.'
fi
[[ "$root" != /mnt/* ]] || die 'Build in the Linux filesystem (for example ~/src/NekoOS), not /mnt/.'
for directory in build build/logs build/sources build/gnupg cache cache/sources out out/images; do
    [[ ! -L "$root/$directory" ]] || die "$directory must not be a symlink."
    mkdir -p "$root/$directory"
done
