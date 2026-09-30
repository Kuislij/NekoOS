#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
source "$root/configs/system-packages.sh"
[[ -n "${FAKEROOTKEY:-}" ]] || die 'Internal command: invoke through bash os build.'
[[ $# == 1 && -f "$1" ]] || die 'Expected a built BusyBox binary.'
stage="$root/build/rootfs"
# Exact generated path under the verified build directory; never accept a caller path.
rm -rf -- "$stage"
mkdir -p "$stage"/{dev/pts,etc/neko/services,home,media,mnt,opt,proc,root,run/lock,state,sys,tmp,usr/bin,usr/include,usr/lib,usr/lib64,usr/local/bin,usr/local/etc/neko/services,usr/local/lib,usr/local/sbin,usr/sbin,usr/share/nekoos/examples,usr/share/nekoos/packages,usr/share/udhcpc,var/cache,var/lib/neko-services/enabled,var/lib/neko-services/disabled,var/log,var/tmp}
# One copy of each program lives under /usr. Classic paths remain available.
ln -s usr/bin "$stage/bin"
ln -s usr/sbin "$stage/sbin"
ln -s usr/lib "$stage/lib"
ln -s usr/lib64 "$stage/lib64"
ln -s ../run "$stage/var/run"
ln -s ../run/lock "$stage/var/lock"
install -m 755 "$1" "$stage/usr/bin/busybox"
toolchain="$root/build/toolchain-root"
[[ -x "$toolchain/usr/bin/tcc" ]] || die 'C toolchain is missing.'
cp -a "$toolchain/usr/include/." "$stage/usr/include/"
cp -a "$toolchain/usr/lib/." "$stage/usr/lib/"
cp -a "$toolchain/lib/ld-musl-x86_64.so.1" "$stage/usr/lib/ld-musl-x86_64.so.1"
install -m 755 "$toolchain/usr/bin/tcc" "$stage/usr/bin/tcc"
ln -s tcc "$stage/usr/bin/cc"
archives=()
for package in "${system_package_archives[@]}"; do
    archives+=("$root/build/system-packages/$package")
done
python3 "$root/tools/system_package.py" install "${archives[@]}" --root "$stage"
"$root/scripts/host-musl-gcc.sh" "$root/tests/pixman_runtime.c" \
    -I "$stage/usr/include/pixman-1" -L "$stage/usr/lib" -lpixman-1 \
    -o "$stage/usr/bin/neko-pixman-check"
readelf -l "$stage/usr/bin/neko-pixman-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' || die 'Pixman probe uses the wrong interpreter.'
readelf -d "$stage/usr/bin/neko-pixman-check" |
    grep -Fq 'libpixman-1.so.0' || die 'Pixman probe is not linked to the packaged library.'
if readelf -d "$stage/usr/bin/neko-pixman-check" | grep -Eq 'RPATH|RUNPATH'; then
    die 'Pixman probe must use the system library path.'
fi
"$root/scripts/host-musl-gcc.sh" "$root/tests/x11_auth_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" -lXau -lXdmcp \
    -o "$stage/usr/bin/neko-x11-base-check"
x11_dynamic="$(readelf -d "$stage/usr/bin/neko-x11-base-check")"
grep -Fq 'libXau.so.6' <<< "$x11_dynamic" || die 'X11 probe lacks libXau.'
grep -Fq 'libXdmcp.so.6' <<< "$x11_dynamic" || die 'X11 probe lacks libXdmcp.'
if grep -Eq 'RPATH|RUNPATH' <<< "$x11_dynamic"; then
    die 'X11 probe must use the system library path.'
fi
"$root/scripts/host-musl-gcc.sh" "$root/tests/xcb_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lxcb \
    -o "$stage/usr/bin/neko-xcb-check"
xcb_dynamic="$(readelf -d "$stage/usr/bin/neko-xcb-check")"
grep -Fq 'libxcb.so.1' <<< "$xcb_dynamic" || die 'XCB probe lacks libxcb.'
if grep -Eq 'RPATH|RUNPATH' <<< "$xcb_dynamic"; then
    die 'XCB probe must use the system library path.'
fi
"$root/scripts/host-musl-gcc.sh" "$root/tests/xlib_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lX11 \
    -o "$stage/usr/bin/neko-xlib-check"
xlib_dynamic="$(readelf -d "$stage/usr/bin/neko-xlib-check")"
grep -Fq 'libX11.so.6' <<< "$xlib_dynamic" || die 'Xlib probe lacks libX11.'
if grep -Eq 'RPATH|RUNPATH' <<< "$xlib_dynamic"; then
    die 'Xlib probe must use the system library path.'
fi
"$root/scripts/host-musl-gcc.sh" "$root/tests/xext_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lXext \
    -o "$stage/usr/bin/neko-xext-check"
xext_dynamic="$(readelf -d "$stage/usr/bin/neko-xext-check")"
grep -Fq 'libXext.so.6' <<< "$xext_dynamic" || die 'Xext probe lacks libXext.'
if grep -Eq 'RPATH|RUNPATH' <<< "$xext_dynamic"; then
    die 'Xext probe must use the system library path.'
fi
for probe in neko-x11-base-check neko-xcb-check neko-xlib-check neko-xext-check; do
    readelf -l "$stage/usr/bin/$probe" |
        grep -Fq '/lib/ld-musl-x86_64.so.1' || die "$probe uses the wrong interpreter."
done
"$root/scripts/host-musl-gcc.sh" "$root/tests/xorg_stack_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lz -ldl \
    -o "$stage/usr/bin/neko-xorg-stack-check"
xorg_dynamic="$(readelf -d "$stage/usr/bin/neko-xorg-stack-check")"
grep -Fq 'libz.so.1' <<< "$xorg_dynamic" || die 'Xorg stack probe lacks zlib.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$xorg_dynamic"; then
    die 'Xorg stack probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-xorg-stack-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Xorg stack probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/xorg_window_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lX11 \
    -o "$stage/usr/bin/neko-xorg-window-check"
xorg_client_dynamic="$(readelf -d "$stage/usr/bin/neko-xorg-window-check")"
grep -Fq 'libX11.so.6' <<< "$xorg_client_dynamic" ||
    die 'Xorg window client lacks Xlib.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$xorg_client_dynamic"; then
    die 'Xorg window client contains a host dependency or build path.'
fi
"$root/scripts/host-musl-gcc.sh" "$root/tests/x11_extensions_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" \
    -lXrandr -lXfixes -lXrender -lXext -lX11 \
    -o "$stage/usr/bin/neko-x11-extensions-check"
x11_extensions_dynamic="$(readelf -d "$stage/usr/bin/neko-x11-extensions-check")"
for library in libXrandr.so.2 libXfixes.so.3 libXrender.so.1; do
    grep -Fq "Shared library: [$library]" <<< "$x11_extensions_dynamic" ||
        die "X11 extension probe lacks $library."
done
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$x11_extensions_dynamic"; then
    die 'X11 extension probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-x11-extensions-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'X11 extension probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/apps/x11-welcome.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lX11 \
    -o "$stage/usr/bin/neko-x11-welcome"
x11_welcome_dynamic="$(readelf -d "$stage/usr/bin/neko-x11-welcome")"
grep -Fq 'Shared library: [libX11.so.6]' <<< "$x11_welcome_dynamic" ||
    die 'X11 welcome window lacks Xlib.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$x11_welcome_dynamic"; then
    die 'X11 welcome window contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-x11-welcome" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'X11 welcome window uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/libffi_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lffi \
    -o "$stage/usr/bin/neko-libffi-check"
libffi_dynamic="$(readelf -d "$stage/usr/bin/neko-libffi-check")"
grep -Fq 'Shared library: [libffi.so.8]' <<< "$libffi_dynamic" ||
    die 'libffi probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$libffi_dynamic"; then
    die 'libffi probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-libffi-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'libffi probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/recipes/libpng/smoke.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lpng16 -lz \
    -o "$stage/usr/bin/neko-libpng-check"
libpng_dynamic="$(readelf -d "$stage/usr/bin/neko-libpng-check")"
grep -Fq 'Shared library: [libpng16.so.16]' <<< "$libpng_dynamic" ||
    die 'libpng probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$libpng_dynamic"; then
    die 'libpng probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-libpng-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'libpng probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/expat_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" -lexpat \
    -o "$stage/usr/bin/neko-expat-check"
expat_dynamic="$(readelf -d "$stage/usr/bin/neko-expat-check")"
grep -Fq 'Shared library: [libexpat.so.1]' <<< "$expat_dynamic" ||
    die 'Expat probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$expat_dynamic"; then
    die 'Expat probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-expat-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Expat probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/freetype_runtime.c" \
    -I "$stage/usr/include/freetype2" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lfreetype \
    -o "$stage/usr/bin/neko-freetype-check"
freetype_dynamic="$(readelf -d "$stage/usr/bin/neko-freetype-check")"
grep -Fq 'Shared library: [libfreetype.so.6]' <<< "$freetype_dynamic" ||
    die 'FreeType probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$freetype_dynamic"; then
    die 'FreeType probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-freetype-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'FreeType probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/fontconfig_runtime.c" \
    -I "$stage/usr/include" -I "$stage/usr/include/freetype2" \
    -L "$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
    -lfontconfig -o "$stage/usr/bin/neko-fontconfig-check"
fontconfig_dynamic="$(readelf -d "$stage/usr/bin/neko-fontconfig-check")"
grep -Fq 'Shared library: [libfontconfig.so.1]' <<< "$fontconfig_dynamic" ||
    die 'Fontconfig probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$fontconfig_dynamic"; then
    die 'Fontconfig probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-fontconfig-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Fontconfig probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/pcre2_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" -lpcre2-8 \
    -o "$stage/usr/bin/neko-pcre2-check"
pcre2_dynamic="$(readelf -d "$stage/usr/bin/neko-pcre2-check")"
grep -Fq 'Shared library: [libpcre2-8.so.0]' <<< "$pcre2_dynamic" ||
    die 'PCRE2 probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$pcre2_dynamic"; then
    die 'PCRE2 probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-pcre2-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'PCRE2 probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/glib_runtime.c" \
    -I "$stage/usr/include/glib-2.0" \
    -I "$stage/usr/lib/glib-2.0/include" \
    -L "$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
    -lgio-2.0 -lgobject-2.0 -lglib-2.0 \
    -o "$stage/usr/bin/neko-glib-check"
glib_dynamic="$(readelf -d "$stage/usr/bin/neko-glib-check")"
for library in libgio-2.0.so.0 libgobject-2.0.so.0 libglib-2.0.so.0; do
    grep -Fq "Shared library: [$library]" <<< "$glib_dynamic" ||
        die "GLib probe lacks $library."
done
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$glib_dynamic"; then
    die 'GLib probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-glib-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'GLib probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/recipes/cairo/smoke.c" \
    -I "$stage/usr/include/cairo" \
    -I "$stage/usr/include/glib-2.0" \
    -I "$stage/usr/lib/glib-2.0/include" \
    -L "$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
    -lcairo-gobject -lcairo -lgobject-2.0 -lglib-2.0 \
    -o "$stage/usr/bin/neko-cairo-check"
cairo_dynamic="$(readelf -d "$stage/usr/bin/neko-cairo-check")"
for library in libcairo.so.2 libcairo-gobject.so.2; do
    grep -Fq "Shared library: [$library]" <<< "$cairo_dynamic" ||
        die "Cairo probe lacks $library."
done
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$cairo_dynamic"; then
    die 'Cairo probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-cairo-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Cairo probe uses the wrong interpreter.'
"$root/scripts/host-musl-gcc.sh" "$root/tests/libxfce4util_runtime.c" \
    -I "$stage/usr/include/xfce4" \
    -I "$stage/usr/include/glib-2.0" \
    -I "$stage/usr/lib/glib-2.0/include" \
    -L "$stage/usr/lib" -Wl,-rpath-link,"$stage/usr/lib" \
    -lxfce4util -lglib-2.0 \
    -o "$stage/usr/bin/neko-libxfce4util-check"
xfce_util_dynamic="$(readelf -d "$stage/usr/bin/neko-libxfce4util-check")"
grep -Fq 'Shared library: [libxfce4util.so.7]' <<< "$xfce_util_dynamic" ||
    die 'Xfce utility probe lacks the packaged library.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$xfce_util_dynamic"; then
    die 'Xfce utility probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-libxfce4util-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Xfce utility probe uses the wrong interpreter.'
# Resolve each new runtime probe only against the assembled NekoOS SDK.
compile_toolkit_probe() {
    local source="$1" output="$2" expected="$3"
    shift 3
    local pkgconf="$root/build/host-tools/pkgconf-2.5.1/install/bin/pkgconf"
    local -a cflags libs
    local dynamic
    read -r -a cflags <<< "$(PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="$stage" PKG_CONFIG_PATH= "$pkgconf" --cflags "$@")"
    read -r -a libs <<< "$(PKG_CONFIG_LIBDIR="$stage/usr/lib/pkgconfig:$stage/usr/share/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR="$stage" PKG_CONFIG_PATH= "$pkgconf" --libs "$@")"
    "$root/scripts/host-musl-gcc.sh" "${cflags[@]}" "$source" \
        -Wl,-rpath-link,"$stage/usr/lib" "${libs[@]}" -o "$stage/usr/bin/$output"
    dynamic="$(readelf -d "$stage/usr/bin/$output")"
    grep -Fq "Shared library: [$expected]" <<< "$dynamic" || die "$output lacks $expected."
    if grep -Eq 'RPATH|RUNPATH|libc.so.6|libstdc\+\+' <<< "$dynamic"; then
        die "$output contains a host dependency or build path."
    fi
    readelf -l "$stage/usr/bin/$output" | grep -Fq '/lib/ld-musl-x86_64.so.1' ||
        die "$output uses the wrong interpreter."
}
compile_toolkit_probe "$root/recipes/fribidi/smoke.c" neko-fribidi-check libfribidi.so.0 fribidi
compile_toolkit_probe "$root/recipes/harfbuzz/smoke.c" neko-harfbuzz-check libharfbuzz.so.0 harfbuzz-gobject freetype2
compile_toolkit_probe "$root/recipes/pango/smoke.c" neko-pango-check libpango-1.0.so.0 pangocairo fontconfig
compile_toolkit_probe "$root/tests/gdk_pixbuf_runtime.c" neko-gdk-pixbuf-check libgdk_pixbuf-2.0.so.0 gdk-pixbuf-2.0
compile_toolkit_probe "$root/recipes/at-spi2-core/smoke.c" neko-atspi-check libatspi.so.0 atk atk-bridge-2.0 atspi-2
bash "$root/scripts/build-gtk-welcome.sh" "$stage/usr/bin/neko-gtk-welcome" "$stage"
"$root/scripts/host-musl-gcc.sh" "$root/tests/evilwm_runtime.c" \
    -I "$stage/usr/include" -L "$stage/usr/lib" \
    -Wl,-rpath-link,"$stage/usr/lib" -lX11 \
    -o "$stage/usr/bin/neko-evilwm-check"
evilwm_client_dynamic="$(readelf -d "$stage/usr/bin/neko-evilwm-check")"
grep -Fq 'Shared library: [libX11.so.6]' <<< "$evilwm_client_dynamic" ||
    die 'Window manager probe lacks Xlib.'
if grep -Eq 'RPATH|RUNPATH|libc.so.6' <<< "$evilwm_client_dynamic"; then
    die 'Window manager probe contains a host dependency or build path.'
fi
readelf -l "$stage/usr/bin/neko-evilwm-check" |
    grep -Fq '/lib/ld-musl-x86_64.so.1' ||
    die 'Window manager probe uses the wrong interpreter.'
bash "$root/scripts/build-neko-desktop.sh" "$root/build/neko-desktop"
install -m 755 "$root/build/neko-desktop" "$stage/usr/bin/neko-desktop"
"$1" --list > "$root/build/busybox-applets.txt"
while IFS= read -r applet; do
    [[ "$applet" == busybox ]] || ln -s busybox "$stage/usr/bin/$applet"
done < "$root/build/busybox-applets.txt"
for applet in sh mount mkdir sleep ifconfig route udhcpc ping wget tar sha256sum flock readlink chown setuidgid; do
    [[ -x "$stage/usr/bin/$applet" ]] || die "Missing required applet: $applet"
done
for applet in init halt poweroff reboot; do
    ln -s ../bin/busybox "$stage/usr/sbin/$applet"
done
install -m 755 "$root/rootfs/usr/bin/neko-help" "$stage/usr/bin/neko-help"
install -m 755 "$root/rootfs/usr/bin/neko-shell" "$stage/usr/bin/neko-shell"
install -m 755 "$root/rootfs/usr/bin/neko-session" "$stage/usr/bin/neko-session"
install -m 755 "$root/rootfs/usr/bin/neko-x11-session" "$stage/usr/bin/neko-x11-session"
install -m 755 "$root/rootfs/usr/bin/neko-boot-status" "$stage/usr/bin/neko-boot-status"
install -m 755 "$root/rootfs/usr/bin/neko-net-status" "$stage/usr/bin/neko-net-status"
install -m 755 "$root/rootfs/usr/bin/neko-service" "$stage/usr/bin/neko-service"
install -m 755 "$root/rootfs/usr/bin/neko-pkg" "$stage/usr/bin/neko-pkg"
install -m 755 "$root/rootfs/usr/share/udhcpc/default.script" "$stage/usr/share/udhcpc/default.script"
install -m 644 "$root/rootfs/usr/share/nekoos/examples/hello.c" \
    "$stage/usr/share/nekoos/examples/hello.c"
python3 "$root/tools/make_package.py" --format 1 --name neko-greet --version 0.1.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.1.0.npkg"
python3 "$root/tools/make_package.py" --name neko-greet --version 0.2.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet-v2.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.2.0.npkg"
python3 "$root/tools/make_package.py" --name neko-greet --version 0.3.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-greet-v3.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-greet-0.3.0.npkg"
python3 "$root/tools/make_package.py" --name neko-companion --version 1.0.0 \
    --license NOASSERTION --depends 'neko-greet>=0.2.0' \
    --file "$root/packages/examples/neko-companion.sh" \
    --output "$stage/usr/share/nekoos/packages/neko-companion-1.0.0.npkg"
python3 "$root/tools/make_package.py" --name neko-theme --version 1.0.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-theme.sh" \
    --resource "share/message.txt=$root/packages/examples/neko-theme-v1.txt" \
    --output "$stage/usr/share/nekoos/packages/neko-theme-1.0.0.npkg"
python3 "$root/tools/make_package.py" --name neko-theme --version 1.1.0 \
    --license NOASSERTION --file "$root/packages/examples/neko-theme.sh" \
    --resource "share/message.txt=$root/packages/examples/neko-theme-v2.txt" \
    --output "$stage/usr/share/nekoos/packages/neko-theme-1.1.0.npkg"
for archive in "$root"/packages/local/*.npkg; do
    [[ -e "$archive" || -L "$archive" ]] || continue
    [[ -f "$archive" && ! -L "$archive" ]] || die "Local package must be a regular file: $archive"
    filename="${archive##*/}"
    [[ "$filename" =~ ^[a-z0-9][a-z0-9.+-]*\.npkg$ ]] || die "Invalid local package filename: $filename"
    [[ ! -e "$stage/usr/share/nekoos/packages/$filename" ]] || die "Duplicate package filename: $filename"
    (( $(stat -c%s "$archive") <= 35651584 )) || die "Local package is too large: $filename"
    install -m 644 "$archive" "$stage/usr/share/nekoos/packages/$filename"
done
install -m 755 "$root/rootfs/init" "$stage/init"
install -m 755 "$root/rootfs/neko-update-init" "$stage/neko-update"
install -m 644 "$root/rootfs/etc/"{group,hosts,inittab,os-release,passwd,profile} "$stage/etc/"
install -m 644 "$root/rootfs/etc/neko/boot-services" "$stage/etc/neko/boot-services"
install -m 755 "$root/rootfs/etc/neko/services/network" "$stage/etc/neko/services/network"
install -m 755 "$root/rootfs/etc/neko/services/desktop" "$stage/etc/neko/services/desktop"
(
    cd "$stage"
    find etc -type f -print0 | sort -z | xargs -0 sha256sum
) > "$stage/usr/share/nekoos/etc-baseline.sha256"
chmod 1777 "$stage/tmp"
chmod 1777 "$stage/var/tmp"
chmod 700 "$stage/root"
mknod -m 600 "$stage/dev/console" c 5 1
mknod -m 666 "$stage/dev/null" c 1 3
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$stage"
    find . -print0 | sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9
) > "$root/out/images/initramfs.cpio.gz.new"
gzip -t "$root/out/images/initramfs.cpio.gz.new"
mv "$root/out/images/initramfs.cpio.gz.new" "$root/out/images/initramfs.cpio.gz"
python3 "$root/tools/validate_image.py" "$root/out/images/initramfs.cpio.gz"
# The maintenance entry point is needed only in the RAM image.
rm -- "$stage/neko-update"

# A small first-stage image mounts the writable system disk and switch_roots.
bootstrap="$root/build/bootstrap-rootfs"
[[ ! -L "$bootstrap" ]] || die 'Bootstrap staging directory must not be a symlink.'
rm -rf -- "$bootstrap"
mkdir -p "$bootstrap"/{bin,dev,proc,sys,sysroot}
install -m 755 "$1" "$bootstrap/bin/busybox"
ln -s busybox "$bootstrap/bin/sh"
install -m 755 "$root/rootfs/early-init" "$bootstrap/init"
mknod -m 600 "$bootstrap/dev/console" c 5 1
mknod -m 666 "$bootstrap/dev/null" c 1 3
find "$bootstrap" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$bootstrap"
    find . -print0 | sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9
) > "$root/out/images/bootstrap.cpio.gz.new"
gzip -t "$root/out/images/bootstrap.cpio.gz.new"
mv "$root/out/images/bootstrap.cpio.gz.new" "$root/out/images/bootstrap.cpio.gz"

# Build a template under the same fakeroot process as the staged rootfs so
# its ownership, permissions and device entries survive into ext4.
template="$root/out/images/system-template.img"
[[ ! -L "$template" && ! -L "$template.new" ]] || die 'System image output must not be a symlink.'
rm -f -- "$template.new"
qemu-img create -f raw "$template.new" 256M
E2FSPROGS_FAKE_TIME="$SOURCE_DATE_EPOCH" mke2fs -t ext4 -F -q -m 0 \
    -L NEKO_SYSTEM -U 4e454b4f-4f53-4000-8000-000000000001 \
    -d "$stage" "$template.new"
[[ "$(blkid -p -s TYPE -o value "$template.new")" == ext4 ]] || die 'System template is not ext4.'
mv "$template.new" "$template"
echo "SYSTEM_TEMPLATE_READY: $template"
