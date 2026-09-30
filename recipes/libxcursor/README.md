# libXcursor 1.2.3

X cursor client library for GTK cursor handling.

Build with `bash recipes/libxcursor/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXcursor-1.2.3.tar.xz).
SHA-256: `fde9402dd4cfe79da71e2d96bb980afc5e6ff4f8a7d74c159e1966afb2b2c2c0`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxcursor/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
