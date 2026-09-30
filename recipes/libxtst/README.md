# libXtst 1.2.5

XTEST extension client library used by AT-SPI accessibility.

Build with `bash recipes/libxtst/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXtst-1.2.5.tar.xz).
SHA-256: `b50d4c25b97009a744706c1039c598f4d8e64910c9fde381994e1cae235d9242`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxtst/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
