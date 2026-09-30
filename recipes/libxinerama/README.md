# libXinerama 1.1.6

Xinerama client library for GTK screen geometry.

Build with `bash recipes/libxinerama/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXinerama-1.1.6.tar.xz).
SHA-256: `d00fc1599c303dc5cbc122b8068bdc7405d6fcb19060f4597fc51bd3a8be51d7`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxinerama/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
