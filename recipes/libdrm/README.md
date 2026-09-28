# libdrm 2.4.134

The recipe builds the core DRM/KMS userspace interface for NekoOS's musl
toolchain. It supplies `libdrm.so.2`, public headers and `libdrm.pc` for an
Xorg modesetting server. QEMU's generic virtio GPU does not require the
vendor-specific libdrm APIs, so they are disabled. This package alone does
not launch Xorg or render a desktop.

The official [upstream archive](https://dri.freedesktop.org/libdrm/libdrm-2.4.134.tar.xz)
is checked against SHA-256
`ac5e74d157830eb8bee44c6a6bf3ad49774ef0dd2a72bdad74a8f20308b52a95`
and SHA-512
`ef2abddea59d1e93c83a48de920431b839ab50d6071ef4da3cf126e7d64ba7b235f2e34e1169d49ad9de2937a0a18acd66bb8d324b067239b1136e0ddbe792a1`.
The recipe includes upstream notices from the core source and build definition;
metadata uses `NOASSERTION` because files in the source carry multiple
permissive notices.

Run `bash recipes/libdrm/build.sh` after preparing the toolchain and pinned
Meson. The output is `build/system-packages/libdrm-2.4.134.nspkg`.
