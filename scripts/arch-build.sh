#!/usr/bin/env bash
# Fetch/verify as the ordinary user; elevate only the isolated image helper.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
(( $# == 0 )) || die 'Usage: bash os arch build'
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 && "$root" != /mnt/* ]] ||
    die 'Use the Linux filesystem of x86_64 Linux / WSL2.'
(( EUID != 0 )) || die 'Run the frontend as a regular user; it elevates only its root helper.'
source "$root/arch/sources.sh"
for command in curl sha256sum gpg tar zstd flock python3; do
    command -v "$command" >/dev/null || die "Missing host tool: $command"
done
for directory in build build/arch cache cache/arch out out/arch; do
    [[ ! -L "$root/$directory" ]] || die "Unsafe directory: $directory"
    mkdir -p "$root/$directory"
done
for file in "$root/build/arch/.fetch.lock" "$root/build/arch/.build.lock"; do
    [[ ! -L "$file" && (! -e "$file" || -f "$file") ]] || die "Unsafe lock: $file"
    touch "$file"
done
exec 8>>"$root/build/arch/.fetch.lock"
flock -n 8 || die 'Another Arch image preparation is running.'
cache="$root/cache/arch"
bootstrap="$cache/bootstrap-$ARCH_BOOTSTRAP_VERSION.tar.zst"
signature="$bootstrap.sig"
fetch() {
    local url="$1" destination="$2"
    [[ ! -L "$destination" && ! -L "$destination.part" &&
       (! -e "$destination" || -f "$destination") ]] || die "Unsafe download path: $destination"
    if [[ ! -f "$destination" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            -o "$destination.part" "$url"
        mv -- "$destination.part" "$destination"
    fi
}
echo 'Подготавливаю проверенную основу Arch Linux для NekoOS.'
fetch "$ARCH_BOOTSTRAP_URL" "$bootstrap"
printf '%s  %s\n' "$ARCH_BOOTSTRAP_SHA256" "$bootstrap" | sha256sum -c -
fetch "$ARCH_BOOTSTRAP_SIGNATURE_URL" "$signature"
keyring="$root/build/arch/gnupg"
[[ ! -L "$keyring" ]] || die 'Release keyring must not be a symlink.'
mkdir -p "$keyring"
chmod 700 "$keyring"
if ! gpg --homedir "$keyring" --list-keys "$ARCH_RELEASE_KEY_FINGERPRINT" >/dev/null 2>&1; then
    gpg --homedir "$keyring" --auto-key-locate clear,wkd \
        --locate-external-key "$ARCH_RELEASE_KEY_EMAIL"
fi
status="$(gpg --homedir "$keyring" --status-fd 1 --verify "$signature" "$bootstrap")" ||
    die 'Arch bootstrap PGP signature verification failed.'
awk -v key="$ARCH_RELEASE_KEY_FINGERPRINT" \
    '$2 == "VALIDSIG" && ($3 == key || $NF == key) { found=1 } END { exit !found }' <<< "$status" ||
    die 'Arch bootstrap was not signed by the pinned release key.'
[[ -f "$root/arch/packages.x86_64" && ! -L "$root/arch/packages.x86_64" &&
   -f "$root/arch/airootfs/usr/local/lib/nekoos/setup-desktop.sh" ]] ||
    die 'The Arch package list or NekoOS desktop profile is missing.'
uid="$(id -u)"
gid="$(id -g)"
echo 'Собираю отдельный диск NekoOS с готовыми пакетами Arch и рабочим столом Xfce.'
if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wsl.exe >/dev/null; then
    wsl.exe -d "$WSL_DISTRO_NAME" -u root -- \
        bash "$root/scripts/arch-build-root.sh" "$root" "$uid" "$gid"
else
    command -v sudo >/dev/null || die 'sudo is required for the isolated image helper outside WSL.'
    sudo -- bash "$root/scripts/arch-build-root.sh" "$root" "$uid" "$gid"
fi
images="$root/out/arch/images"
[[ -d "$images" && ! -L "$images" && -f "$images/SHA256SUMS" && ! -L "$images/SHA256SUMS" ]] ||
    die 'The Arch image helper did not publish safe image outputs.'
(cd "$images" && sha256sum --strict -c SHA256SUMS)
echo 'ARCH_BUILD_READY: out/arch/images/system-template.img'
