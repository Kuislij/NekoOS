#!/usr/bin/env bash
# Build the reference D-Bus session bus and low-level client library for NekoOS.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/dbus/build.sh'

version=1.16.2
archive=dbus-$version.tar.xz
url=https://dbus.freedesktop.org/releases/dbus/$archive
# Published at https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz.sha256sum
sha256=0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2
sha512=5c26f52d85984bb9ae1dde8d7e73921eacbdf020a61ff15f00a4c240cb38a121553ee04bd66e62b28425ff9bc50f4f5e15135166573ac0888332a01a0db1faa2
pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
meson_source="$root/build/host-tools/meson-1.10.1"
meson=(python3 "$meson_source/meson.py")
expat_package="$root/build/system-packages/expat-2.8.5.nspkg"

[[ -f "$root/build/host-musl-gcc.specs" && -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
    die 'Build the pinned musl toolchain first (bash os build).'
[[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
    die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
[[ -f "$meson_source/meson.py" && "$("${meson[@]}" --version)" == 1.10.1 ]] ||
    die 'Build the pinned host Meson first (bash recipes/pixman/build.sh).'
[[ -f "$expat_package" ]] || die "Missing prerequisite package: $expat_package"
python3 "$root/tools/system_package.py" verify "$expat_package" >/dev/null
for tool in curl sha256sum sha512sum tar ninja python3 readelf strip strings find readlink; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

source_file="$root/cache/sources/$archive"
if [[ ! -f "$source_file" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        -o "$source_file.part" "$url"
    printf '%s  %s\n' "$sha256" "$source_file.part" | sha256sum -c -
    mv -- "$source_file.part" "$source_file"
fi
printf '%s  %s\n' "$sha256" "$source_file" | sha256sum -c -
printf '%s  %s\n' "$sha512" "$source_file" | sha512sum -c -

work="$root/build/system-package-build/dbus-$version"
[[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
    die 'Package work directory must not be a symlink.'
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/stage" "$work/sysroot" "$root/build/system-packages"
sysroot="$work/sysroot"
stage="$work/stage"
python3 "$root/tools/system_package.py" install "$expat_package" \
    --root "$sysroot" >/dev/null
[[ -f "$sysroot/usr/lib/pkgconfig/expat.pc" &&
   -f "$sysroot/usr/include/expat.h" &&
   -L "$sysroot/usr/lib/libexpat.so.1" ]] ||
    die 'Expat runtime and development files are missing from the target sysroot.'

tar --no-same-owner -xf "$source_file" -C "$work/sources"
src="$work/sources/dbus-$version"

cat > "$work/musl-x86_64.ini" <<EOF
[binaries]
c = '$root/scripts/host-musl-gcc.sh'
ar = '$(command -v ar)'
strip = '$(command -v strip)'
pkg-config = '$pkgconf'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

(
    export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig"
    export PKG_CONFIG_SYSROOT_DIR="$sysroot"
    export CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos -I$sysroot/usr/include"
    export LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib"
    unset PKG_CONFIG_PATH
    "${meson[@]}" setup "$work/build" "$src" \
        --cross-file "$work/musl-x86_64.ini" --prefix=/usr --libdir=lib \
        --sysconfdir=/etc --localstatedir=/var --buildtype=release \
        --wrap-mode=nofallback -Ddefault_library=shared \
        -Dmessage_bus=true -Dtools=true -Dtraditional_activation=true \
        -Dmodular_tests=disabled -Dinstalled_tests=false \
        -Dxml_docs=disabled -Ddoxygen_docs=disabled -Dducktype_docs=disabled \
        -Dqt_help=disabled -Dvalgrind=disabled -Drelocation=disabled \
        -Dapparmor=disabled -Dselinux=disabled -Dlibaudit=disabled \
        -Dsystemd=disabled -Dlaunchd=disabled -Dx11_autolaunch=disabled \
        -Dsession_socket_dir=/tmp
    "${meson[@]}" compile -C "$work/build" -j "${JOBS:-4}"
    DESTDIR="$stage" "${meson[@]}" install -C "$work/build" --no-rebuild
)

# A system bus needs a privileged launch helper and a service account, which
# this session-bus package does not provision.
rm -rf -- "$stage/usr/share/doc" "$stage/usr/share/man" "$stage/usr/share/locale" \
    "$stage/usr/libexec" "$stage/etc" "$stage/run" "$stage/var"
rm -f -- "$stage/usr/share/dbus-1/system.conf"
find "$stage/usr/lib" -type f -name '*.la' -delete
install -Dm 644 "$src/COPYING" "$stage/usr/share/licenses/dbus/COPYING"
for name in AFL-2.1 GPL-2.0-or-later MIT; do
    install -Dm 644 "$src/LICENSES/$name.txt" \
        "$stage/usr/share/licenses/dbus/$name.txt"
done

library="$stage/usr/lib/libdbus-1.so.3"
[[ -L "$library" && -L "$stage/usr/lib/libdbus-1.so" &&
   -f "$stage/usr/lib/pkgconfig/dbus-1.pc" &&
   -f "$stage/usr/include/dbus-1.0/dbus/dbus.h" &&
   -f "$stage/usr/lib/dbus-1.0/include/dbus/dbus-arch-deps.h" &&
   -x "$stage/usr/bin/dbus-daemon" &&
   -x "$stage/usr/bin/dbus-run-session" &&
   -f "$stage/usr/share/dbus-1/session.conf" ]] ||
    die 'D-Bus session daemon, shared library, config or development files are missing.'
grep -Fq "Version: $version" "$stage/usr/lib/pkgconfig/dbus-1.pc" ||
    die 'D-Bus pkg-config version is wrong.'

for binary in "$stage/usr/lib/libdbus-1.so.3" "$stage/usr/bin"/dbus-*; do
    binary="$(readlink -f "$binary")"
    strip --strip-unneeded "$binary"
    dynamic="$(readelf -d "$binary")"
    grep -Fq 'Shared library: [libc.so]' <<< "$dynamic" ||
        die "D-Bus binary is not linked against NekoOS musl: $binary"
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic" ||
       strings "$binary" | grep -F "$root/" >/dev/null; then
        die "D-Bus binary contains a host runtime dependency or build path: $binary"
    fi
    if [[ "$binary" == "$stage/usr/bin/"* ]]; then
        grep -Fq '[Requesting program interpreter: /lib/ld-musl-x86_64.so.1]' \
            <<< "$(readelf -l "$binary")" ||
            die "D-Bus executable has the wrong dynamic loader: $binary"
    fi
done
grep -Fq 'Library soname: [libdbus-1.so.3]' \
    <<< "$(readelf -d "$(readlink -f "$library")")" ||
    die 'D-Bus shared library SONAME is wrong.'
grep -Fq 'Shared library: [libexpat.so.1]' \
    <<< "$(readelf -d "$stage/usr/bin/dbus-daemon")" ||
    die 'D-Bus daemon does not link to the NekoOS Expat ABI.'

package="$root/build/system-packages/dbus-$version.nspkg"
python3 "$root/tools/system_package.py" build \
    --root "$stage" --name dbus --version "$version" --arch x86_64 \
    --license GPL-2.0-or-later --source-sha256 "$sha256" \
    --depends 'expat>=2.8.5' --output "$package"
python3 "$root/tools/system_package.py" verify "$package"
printf 'DBUS_PACKAGE_READY: %s\n' "$package"
