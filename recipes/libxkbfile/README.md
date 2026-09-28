# libxkbfile 1.2.0

This recipe cross-builds the X.Org XKB configuration file parser for NekoOS
musl. Xorg and keyboard utilities use this library to read XKB keymaps. The
NSPKG/1 package includes `libxkbfile.so.1`, development headers, `xkbfile.pc`,
and the full upstream `COPYING` notice. It does not provide keyboard layout
data or the `xkbcomp` program.

Official source: [`libxkbfile-1.2.0.tar.xz`](https://xorg.freedesktop.org/archive/individual/lib/libxkbfile-1.2.0.tar.xz).
The [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01871.html)
publishes the hashes checked by the recipe:

- SHA-256: `7f71884e5faf56fb0e823f3848599cf9b5a9afce51c90982baeb64f635233ebf`
- SHA-512: `772035b6bc1d692e8141e095fc2a8cf2ba7daed1d7148def862103160e0d7706f46865367befbbe4c777e7311b224d2cd4474f399d747b122dd395deac3e7cb7`

Version 1.2.0 is Meson-only. The recipe uses the pinned host Meson 1.10.1 and
pkgconf 2.5.1 with a cross file for the NekoOS musl toolchain. Its build
sysroot consists exclusively of verified NekoOS `xorgproto`, `xtrans`,
`libxau`, `libxdmcp`, `libxcb`, and `libx11` packages. Run
`bash recipes/libxkbfile/build.sh` in the Linux checkout after building those
prerequisites. The output is
`build/system-packages/libxkbfile-1.2.0.nspkg`.

The package metadata uses `NOASSERTION` because the upstream `COPYING` file
contains several distinct permissive notices; its full contents are included.
