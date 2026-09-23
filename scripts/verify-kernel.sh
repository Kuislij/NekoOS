#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
keyhome="$root/build/gnupg"
mkdir -p "$keyhome"
chmod 700 "$keyhome"
fingerprints="$(gpg --homedir "$keyhome" --batch --with-colons --show-keys \
    "$root/keys/linux-stable.asc" | awk -F: \
    '$1 == "pub" { primary=1; next } $1 == "fpr" && primary { print $10; primary=0 }')"
[[ "$fingerprints" == 647F28654894E3BD457199BE38DBBDC86092693E ]] || die 'Unexpected Linux signing key.'
signature="$root/cache/sources/linux-$LINUX_VERSION.tar.sign"
if [[ ! -f "$signature" ]]; then
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --retry 3 --connect-timeout 30 -o "$signature.part" "${LINUX_URL%.xz}.sign"
    mv "$signature.part" "$signature"
fi
gpg --homedir "$keyhome" --batch --yes --dearmor \
    --output "$keyhome/linux-stable.gpg" "$root/keys/linux-stable.asc"
xz -cd "$root/cache/sources/${LINUX_URL##*/}" | \
    gpgv --homedir "$keyhome" --keyring "$keyhome/linux-stable.gpg" "$signature" -
