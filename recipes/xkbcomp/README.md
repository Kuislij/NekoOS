# xkbcomp 1.5.0

This recipe cross-builds the X.Org XKB keymap compiler for NekoOS musl. The
NSPKG/1 package contains `/usr/bin/xkbcomp`, its `xkbcomp.pc` metadata, and
the upstream `COPYING` notice. It depends on the NekoOS `libxkbfile`, `libx11`,
and `xorgproto` packages. Bison runs only on the Linux build host to generate
the parser; it is not installed in the guest image.

Official source: [`xkbcomp-1.5.0.tar.xz`](https://xorg.freedesktop.org/archive/individual/app/xkbcomp-1.5.0.tar.xz).
The [X.Org release announcement](https://lists.x.org/archives/xorg-announce/2025-December/003645.html)
publishes the hashes checked by the recipe:

- SHA-256: `2ac31f26600776db6d9cd79b3fcd272263faebac7eb85fb2f33c7141b8486060`
- SHA-512: `d8ef4906261251e2600b3650660fbe88ed99a44694f1e59b433e0811f1ab5234c4f2f0b3647fa5372fb0f46b56eac60c0219a762bf1af0ab06226b63e4a6b081`

The recipe uses pinned host Meson 1.10.1 and pkgconf 2.5.1 with a cross file
for NekoOS musl, and a sysroot assembled from verified NSPKG/1 packages. Run
`bash recipes/xkbcomp/build.sh` in the Linux checkout after building those
prerequisites. The output is `build/system-packages/xkbcomp-1.5.0.nspkg`.

The compiled-in XKB data root is `/usr/share/X11/xkb`. Actual keyboard layouts
need the separate `xkeyboard-config` data package. The metadata uses
`NOASSERTION` for the multiple permissive notices collected in `COPYING`.
