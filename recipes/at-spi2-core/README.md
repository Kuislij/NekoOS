# AT-SPI2 core 2.58.9

This package includes ATK (`libatk-1.0`), AT-SPI (`libatspi`), the GTK accessibility bridge (`libatk-bridge-2.0`), the accessibility bus launcher and registry daemon, headers, pkg-config files and D-Bus service configuration.

Build with `bash recipes/at-spi2-core/build.sh` after GLib, D-Bus, libXi, libXtst and their prerequisite NSPKG packages. All target dependencies are loaded from an isolated packaged sysroot. Code generators are pure Python scripts extracted from the hash-checked GLib 2.84.4 source.

Source: [GNOME release archive](https://download.gnome.org/sources/at-spi2-core/2.58/at-spi2-core-2.58.9.tar.xz).
SHA-256: `c8eacbe2640038178f2c2cd7abef2c23c7a4777909119f9d815c7151b39fb82a`, matching the [published release digest](https://download.gnome.org/sources/at-spi2-core/2.58/at-spi2-core-2.58.9.sha256sum). SHA-512 is pinned too.

The build disables optional introspection, Python GI overrides, documentation, systemd units, the GTK2 module and upstream test executables. The pinned source has no test build option: the recipe checks and replaces exactly the test subdirectory and its libxml2-only test dependency; runtime accessibility code remains included. This avoids an unused libxml2 guest dependency.

License: LGPL-2.1-or-later. Upstream `COPYING` is installed at `/usr/share/licenses/at-spi2-core/COPYING`. All ELF files are checked for musl linkage and absence of host runtime/search paths. `smoke.c` exercises ATK state, object name/role, AT-SPI GType registration and bridge library linkage without requiring a graphical display or session bus.
