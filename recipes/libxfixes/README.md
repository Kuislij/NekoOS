# libXfixes

NekoOS builds libXfixes 6.0.2 from the [official X.Org archive](https://xorg.freedesktop.org/archive/individual/lib/libXfixes-6.0.2.tar.xz) against its musl toolchain. The recipe verifies both SHA-256 and SHA-512 before extraction and produces `libxfixes-6.0.2.nspkg` with the shared library, Xlib extension header, pkg-config file, and upstream `COPYING` notice.

The extension provides region and cursor operations used by desktop components. It does not itself create a graphical session.
