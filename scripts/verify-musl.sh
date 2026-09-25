#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
keyhome="$root/build/gnupg"
fingerprints="$(gpg --homedir "$keyhome" --batch --with-colons --show-keys \
    "$root/keys/musl-release.asc" | awk -F: \
    '$1 == "pub" { primary=1; next } $1 == "fpr" && primary { print $10; primary=0 }')"
[[ "$fingerprints" == 836489290BB6B70F99FFDA0556BCDB593020450F ]] || \
    die 'Unexpected musl signing key.'
signature="$root/cache/sources/musl-$MUSL_VERSION.tar.gz.asc"
if [[ ! -f "$signature" ]]; then
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 \
        --connect-timeout 30 -o "$signature.part" "$MUSL_URL.asc"
    mv "$signature.part" "$signature"
fi
gpg --homedir "$keyhome" --batch --yes --dearmor \
    --output "$keyhome/musl-release.gpg" "$root/keys/musl-release.asc"
gpgv --homedir "$keyhome" --keyring "$keyhome/musl-release.gpg" \
    "$signature" "$root/cache/sources/musl-$MUSL_VERSION.tar.gz"
