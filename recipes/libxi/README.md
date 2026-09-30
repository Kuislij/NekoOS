# libXi 1.8.3

X Input Extension client library, including XInput2 tablet and pointer support.

Build with `bash recipes/libxi/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXi-1.8.3.tar.xz).
SHA-256: `7ad60056f01af4f786cfe93b3a7707447711626fc8da2637bec71a90409babe5`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxi/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
