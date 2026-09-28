# libevdev 1.13.7

This recipe builds the upstream evdev helper library for the NekoOS musl
toolchain. It provides `libevdev.so.2`, public headers and `libevdev.pc` for
the separate X.Org evdev input driver recipe. The pinned source is the
[official freedesktop.org release](https://www.freedesktop.org/software/libevdev/libevdev-1.13.7.tar.xz)
listed in the [upstream release directory](https://www.freedesktop.org/software/libevdev/).
Both checksums are verified before extraction:

- SHA-256: `0caf824971108f15bb2ad356433bae198d7d3bf1e82d43f63626e069e060bfa6`
- SHA-512: `fd64ded32a7f303d45d545ebf293cc9d1a1e79672e1d5879d05e2c723b78709d1ecc972afb1f043eafe961cbded06d221a6fccc25ebba00a68fcf76e4ee3da8b`

The build uses the pinned Meson host tool and NekoOS musl compiler. Upstream
tests, debugging tools and documentation generation are disabled for this
runtime package; the shared library itself is built from the unmodified
archive. No host-distribution library is used for the guest binary. Run
`bash recipes/libevdev/build.sh` in the Linux checkout; the result is
`build/system-packages/libevdev-1.13.7.nspkg`.

The upstream `COPYING` includes an MIT/Expat notice and a Linux kernel header
notice. It is installed in full; the package metadata uses `NOASSERTION`
until those notices have a precise combined license expression.
