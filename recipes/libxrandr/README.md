# libXrandr

NekoOS builds libXrandr 1.5.5 from the [official X.Org archive](https://xorg.freedesktop.org/archive/individual/lib/libXrandr-1.5.5.tar.xz) against its musl toolchain. The recipe verifies both SHA-256 and SHA-512 before extraction and produces `libxrandr-1.5.5.nspkg` with the shared library, Xlib extension header, pkg-config file, and upstream `COPYING` notice.

libXrandr depends on libXrender and libXext and is used by the first independent X11 window manager. NekoOS tests the extension against its actual Xorg server in QEMU.
