#!/usr/bin/env bash
# Shared, pinned source build for the small X.Org client extension libraries.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../scripts/common.sh"

build_x11_extension() {
    : "${x11_name:?}" "${x11_upstream:?}" "${x11_version:?}"
    : "${x11_sha256:?}" "${x11_sha512:?}" "${x11_soname:?}"
    : "${x11_header:?}" "${x11_pc:?}"
    (( ${#x11_prerequisites[@]} > 0 )) || die 'Missing X11 build prerequisites.'

    [[ -f "$root/build/host-musl-gcc.specs" &&
       -f "$root/build/toolchain-root/usr/lib/libc.so" ]] ||
        die 'Build the pinned musl toolchain first (bash os build).'
    local pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
    [[ -x "$pkgconf" && "$("$pkgconf" --version)" == 2.5.1 ]] ||
        die 'Build the pinned host pkgconf first (bash recipes/pkgconf/build.sh).'
    local tool
    for tool in curl sha256sum sha512sum tar make python3 readelf strip strings; do
        command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
    done

    local archive="$x11_upstream-$x11_version.tar.xz"
    local url="https://xorg.freedesktop.org/archive/individual/lib/$archive"
    local source_file="$root/cache/sources/$archive"
    if [[ ! -f "$source_file" ]]; then
        curl --fail --location --proto '=https' --proto-redir '=https' \
            --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
            -o "$source_file.part" "$url"
        printf '%s  %s\n' "$x11_sha256" "$source_file.part" | sha256sum -c -
        mv -- "$source_file.part" "$source_file"
    fi
    printf '%s  %s\n' "$x11_sha256" "$source_file" | sha256sum -c -
    printf '%s  %s\n' "$x11_sha512" "$source_file" | sha512sum -c -

    local package file
    local -a archives=()
    for package in "${x11_prerequisites[@]}"; do
        file="$root/build/system-packages/$package"
        [[ -f "$file" ]] || die "Missing prerequisite system package: $file"
        python3 "$root/tools/system_package.py" verify "$file" >/dev/null
        archives+=("$file")
    done

    local work="$root/build/system-package-build/$x11_name-$x11_version"
    [[ ! -L "$root/build/system-package-build" && ! -L "$work" ]] ||
        die 'Package work directory must not be a symlink.'
    rm -rf -- "$work"
    mkdir -p "$work/sources" "$work/build" "$work/stage" "$work/sysroot" \
        "$root/build/system-packages"
    local sysroot="$work/sysroot" stage="$work/stage"
    python3 "$root/tools/system_package.py" install "${archives[@]}" \
        --root "$sysroot" >/dev/null
    tar --no-same-owner -xf "$source_file" -C "$work/sources"
    local src="$work/sources/$x11_upstream-$x11_version"
    [[ -x "$src/configure" && -f "$src/COPYING" ]] ||
        die "Incomplete upstream archive: $archive"
    (
        cd "$work/build"
        export PKG_CONFIG="$pkgconf"
        export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
        export PKG_CONFIG_SYSROOT_DIR="$sysroot"
        unset PKG_CONFIG_PATH
        CPPFLAGS="-I$sysroot/usr/include" \
        CFLAGS="-O2 -ffile-prefix-map=$root=/usr/src/nekoos" \
        LDFLAGS="-Wl,-rpath-link,$sysroot/usr/lib" \
        CC="$root/scripts/host-musl-gcc.sh" \
        "$src/configure" --build=x86_64-pc-linux-gnu --host=x86_64-linux-musl \
            --prefix=/usr --libdir=/usr/lib --mandir=/usr/share/man \
            --enable-shared --disable-static
        make -j "${JOBS:-4}"
        make DESTDIR="$stage" install
    )
    find "$stage/usr/lib" -maxdepth 1 -name '*.la' -type f -delete

    local library
    library="$(find "$stage/usr/lib" -maxdepth 1 -type f \
        -name "$x11_soname.*" -print -quit)"
    [[ -n "$library" && -L "$stage/usr/lib/$x11_upstream.so" &&
       -L "$stage/usr/lib/$x11_soname" &&
       -f "$stage/usr/include/$x11_header" &&
       -f "$stage/usr/lib/pkgconfig/$x11_pc" ]] ||
        die "$x11_name runtime or development files are missing."
    strip --strip-unneeded "$library"
    install -Dm 644 "$src/COPYING" \
        "$stage/usr/share/licenses/$x11_name/COPYING"

    local dynamic
    dynamic="$(readelf -d "$library")"
    grep -Fq "Library soname: [$x11_soname]" <<< "$dynamic" ||
        die "$x11_name SONAME is wrong."
    local needed
    for needed in "${x11_runtime_needed[@]}"; do
        grep -Fq "Shared library: [$needed]" <<< "$dynamic" ||
            die "$x11_name lacks expected runtime dependency $needed."
    done
    if grep -Eq '\((RPATH|RUNPATH)\)' <<< "$dynamic" ||
       grep -Fq 'Shared library: [libc.so.6]' <<< "$dynamic"; then
        die "$x11_name contains a host runtime dependency or build path."
    fi
    if strings "$library" | grep -F "$root/" >/dev/null; then
        die "$x11_name contains an absolute build path."
    fi

    package="$root/build/system-packages/$x11_name-$x11_version.nspkg"
    local -a dep_args=()
    for needed in "${x11_depends[@]}"; do
        dep_args+=(--depends "$needed")
    done
    python3 "$root/tools/system_package.py" build \
        --root "$stage" --name "$x11_name" --version "$x11_version" \
        --arch x86_64 --license NOASSERTION --source-sha256 "$x11_sha256" \
        "${dep_args[@]}" --output "$package"
    python3 "$root/tools/system_package.py" verify "$package"
    printf 'X11_EXTENSION_PACKAGE_READY: %s\n' "$package"
}
