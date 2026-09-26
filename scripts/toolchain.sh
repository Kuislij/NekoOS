#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
(( $# == 0 )) || die 'Internal command: invoke through bash os build.'
kernel="$root/build/sources/linux-$LINUX_VERSION"
kout="$root/build/linux-$LINUX_VERSION"
musl="$root/build/sources/musl-$MUSL_VERSION"
tcc="$root/build/sources/tcc-$TCC_VERSION"
stage="$root/build/toolchain-root"
jobs="${JOBS:-4}"
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die 'JOBS must be a positive integer.'
for component in "$kernel" "$musl" "$tcc"; do
    [[ -f "$component/.neko-extracted" ]] || die "Source was not verified: $component"
done
if [[ ! -f "$musl/.neko-configured" ]]; then
    (cd "$musl"; ./configure --prefix=/usr --syslibdir=/lib)
    touch "$musl/.neko-configured"
fi
make -C "$musl" -j"$jobs"
# Stage musl before compiling the guest utilities. The generated specs point
# at this exact staging tree, while installed guest specs retain /usr paths.
rm -rf -- "$stage"
mkdir -p "$stage"
make -C "$kernel" O="$kout" ARCH=x86_64 \
    INSTALL_HDR_PATH="$stage/usr" headers_install
make -C "$musl" DESTDIR="$stage" install
sed -e "s@/usr/include@$stage/usr/include@g" \
    -e "s@/usr/lib@$stage/usr/lib@g" \
    "$stage/usr/lib/musl-gcc.specs" > "$root/build/host-musl-gcc.specs"
[[ -s "$root/build/host-musl-gcc.specs" ]] || die 'Host musl compiler specs are missing.'
tcc_options=(--prefix=/usr --config-musl --extra-ldflags=-static
    --cc="$root/scripts/host-musl-gcc.sh"
    --elfinterp=/lib/ld-musl-x86_64.so.1 --crtprefix=/usr/lib
    --libpaths=/usr/lib:/lib '--sysincludepaths={B}/include:/usr/include')
tcc_config="$(printf '%s\n' "${tcc_options[@]}")"
if [[ ! -f "$tcc/.neko-configured" || "$(cat "$tcc/.neko-configured")" != "$tcc_config" ]]; then
    (cd "$tcc"; ./configure "${tcc_options[@]}")
    make -C "$tcc" clean
    printf '%s\n' "$tcc_config" > "$tcc/.neko-configured"
fi
make -C "$tcc" -j"$jobs"
make -C "$tcc" DESTDIR="$stage" install
[[ -x "$stage/usr/bin/tcc" && -f "$stage/usr/lib/libc.a" &&
   -f "$stage/usr/include/stdio.h" && -f "$stage/usr/include/linux/version.h" ]] ||
    die 'Incomplete C toolchain staging.'
if readelf -l "$stage/usr/bin/tcc" | grep -q INTERP; then
    die 'The guest C compiler must be statically linked.'
fi
echo 'TOOLCHAIN_READY: TinyCC, musl and Linux headers'
