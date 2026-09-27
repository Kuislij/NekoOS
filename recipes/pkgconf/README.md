# pkgconf 2.5.1 (build host only)

The NekoOS build host may not have `pkg-config` installed. This recipe builds
pkgconf from its [upstream release](https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz)
with pinned SHA-256
`cd05c9589b9f86ecf044c10a2269822bc9eb001eced2582cfffd658b0a50c243`.
It puts the tool under `build/host-tools/pkgconf-2.5.1/install/bin/pkgconf`.
This is a build tool for future X11 libraries; it is not copied into the guest.

Run `bash recipes/pkgconf/build.sh` after preparing the Linux host. Cross
recipes must set `PKG_CONFIG_LIBDIR` to the staged target `.pc` directories and
`PKG_CONFIG_SYSROOT_DIR` to the target sysroot when using it. No host library
paths should enter target compiler or linker flags.
