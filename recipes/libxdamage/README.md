# libXdamage 1.1.7

Damage extension client library needed by GTK's X11 backend.

Build with `bash recipes/libxdamage/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXdamage-1.1.7.tar.xz).
SHA-256: `127067f521d3ee467b97bcb145aeba1078e2454d448e8748eb984d5b397bde24`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxdamage/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
