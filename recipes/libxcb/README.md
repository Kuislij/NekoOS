# libxcb 1.17.0

This recipe cross-builds the upstream X C Binding library against NekoOS musl.
Its resulting NSPKG/1 system package contains shared libraries, public headers,
pkg-config metadata and the upstream license. The build-time dependencies are
the verified NekoOS `xorgproto`, `libxau` and `libxdmcp` packages, the pinned
host `pkgconf` tool, and source-built host-only `xcb-proto` XML/Python code
generation data. No host-distribution binary is copied into the guest package.

Official source: [`libxcb-1.17.0.tar.xz`](https://xcb.freedesktop.org/dist/libxcb-1.17.0.tar.xz).
The [X.Org release announcement](https://lists.x.org/archives/xorg-announce/2024-April/003507.html)
publishes the checksums verified by the recipe:

- SHA-256: `599ebf9996710fea71622e6e184f3a8ad5b43d0e5fa8c4e407123c88a59a6d55`
- SHA-512: `945b1f28e8b407a4d0ebf88c99ef3cbef763fd75e6eaa8e971946e44ce8dbe9b478c56ae85aaaadab7fdb25987e88570d9d4fb9ad2febd6d6bf21d644a0e10d0`

The upstream `COPYING` contains the MIT-style permission notice and is staged
under `/usr/share/licenses/libxcb`. The package declares runtime dependencies
on `libxau`, `libxdmcp` and `xorgproto`; `xcb-proto` and `pkgconf` are kept on
the build host only.

After building the prerequisites, run `bash recipes/libxcb/build.sh` in the
Linux checkout. The package is
`build/system-packages/libxcb-1.17.0.nspkg`. The temporary sysroot, source,
build tree and install staging area remain under
`build/system-package-build/libxcb-1.17.0/` for inspection.
