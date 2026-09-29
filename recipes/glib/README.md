# GLib 2.84.4

This recipe cross-builds the GLib, GObject and GIO shared libraries, headers,
pkg-config metadata and guest utilities for NekoOS musl. It requires the
`libffi-3.5.2`, `pcre2-10.48` and `zlib-1.3.2` NSPKG packages plus pinned host
Meson 1.10.1 and pkgconf 2.5.1. Run `bash recipes/glib/build.sh` on the Linux
build host. The output is `build/system-packages/glib-2.84.4.nspkg`.

The source is the [official GNOME release](https://download.gnome.org/sources/glib/2.84/glib-2.84.4.tar.xz).
Its [published SHA-256 checksum](https://download.gnome.org/sources/glib/2.84/glib-2.84.4.sha256sum)
is `8a9ea10943c36fc117e253f80c91e477b673525ae45762942858aef57631bb90`.
The recipe also pins SHA-512
`2de9b2f7376c0e5f6ee585087090675d597c474199a10d04aad18df688b6ca77d17e93a86ec07482898663f51c82121992272496318138f77ca5ad2c340a4bd3`.

The first-stage cross build disables tests, introspection data, translations,
documentation, SELinux, libmount and tracing. These features require further
host tools or separately packaged target libraries. The core GLib, GObject and
GIO APIs remain available through `glib-2.0.pc`, `gobject-2.0.pc` and
`gio-2.0.pc`; `gio-unix-2.0.pc` is also included. Upstream licensing files are
kept under `/usr/share/licenses/glib/`.

Guest utilities such as `gio`, `gdbus`, `gsettings` and
`glib-compile-schemas` are musl ELF executables. Upstream Python generators
(`gdbus-codegen`, `glib-genmarshal`, `glib-mkenums`, `gtester-report`) and
the Autotools helper `glib-gettextize` are omitted until NekoOS has their
interpreters and build tools. Native builders should use their host copies.
