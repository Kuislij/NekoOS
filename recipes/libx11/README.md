# libX11 1.8.13

This recipe cross-builds the upstream Xlib client library for NekoOS musl. The
NSPKG/1 package includes `libX11.so.6`, public Xlib headers, `x11.pc`, X11
locale data and the upstream `COPYING` notices. It is a library for X11 clients;
an X server is still required to display windows.

Official source: [`libX11-1.8.13.tar.xz`](https://xorg.freedesktop.org/archive/individual/lib/libX11-1.8.13.tar.xz).
The [X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg08248.html)
publishes the hashes checked by the recipe:

- SHA-256: `69606f485c2c07c14ef64f75b7bb326d48587af33795d9ab3e607c0b5f94f11c`
- SHA-512: `4c4a098eaff09a51309f3f322bc435ccd022c8f753974eb2650b60e42b737077ca0fde0df82b53f4ba8ed2388bbc8cb59ba66cc9946ae2b5907d7d1a9580e03d`

Build-time inputs are verified NekoOS `xorgproto`, `xtrans`, `libxcb`,
`libxau`, and `libxdmcp` packages, plus the host-only pinned `pkgconf`. The
release tarball has a generated `configure` script, so no host Autotools
regeneration is needed. `makekeys` is built with the host compiler but never
installed in the guest; the shared library is built with the musl toolchain.

Run `bash recipes/libx11/build.sh` in the Linux checkout after building these
prerequisites. The output is
`build/system-packages/libx11-1.8.13.nspkg`. The package metadata uses
`NOASSERTION` because `COPYING` and individual files contain several distinct
permissive notices; the complete upstream `COPYING` is included.
The recipe strips target-library debug symbols and omits man pages from this
early-boot package; X11 locale data and development headers remain included.
