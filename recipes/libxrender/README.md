# libXrender

NekoOS builds libXrender 0.9.12 from the [official X.Org archive](https://xorg.freedesktop.org/archive/individual/lib/libXrender-0.9.12.tar.xz) against its musl toolchain. The recipe verifies both SHA-256 and SHA-512 before extraction and produces `libxrender-0.9.12.nspkg` with the shared library, Xlib extension header, pkg-config file, and upstream `COPYING` notice.

The extension is needed by X11 desktop toolkits and by libXrandr. It does not itself create a graphical session.
