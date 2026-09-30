# libXcomposite 0.4.7

Composite extension client library needed by GTK's X11 backend.

Build with `bash recipes/libxcomposite/build.sh` after its packaged prerequisites and the musl toolchain. This uses the shared X.Org extension recipe: isolated packaged sysroot, musl shared library and headers, pkg-config metadata, preserved upstream `COPYING`, ELF dependency and path checks, and deterministic NSPKG packing.

Source: [official X.Org release archive](https://xorg.freedesktop.org/archive/individual/lib/libXcomposite-0.4.7.tar.xz).
SHA-256: `8bdf310967f484503fa51714cf97bff0723d9b673e0eecbf92b3f97c060c8ccb`. SHA-512 is also pinned in the recipe.

Upstream licenses are preserved at `/usr/share/licenses/libxcomposite/COPYING`; package metadata uses `NOASSERTION` for the collection of upstream notices.
