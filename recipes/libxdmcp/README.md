# libXdmcp 1.1.5

libXdmcp supplies the X Display Manager Control Protocol functions used by
parts of the X11 stack. This recipe builds its musl-linked shared library,
public header, and `xdmcp.pc` as an NekoOS system package. It requires
`xorgproto-2025.1` headers at build time.

Upstream archive: <https://xorg.freedesktop.org/archive/individual/lib/libXdmcp-1.1.5.tar.xz>.
The official [X.Org release announcement](https://lists.x.org/archives/xorg-announce/2024-March/003467.html)
publishes SHA-256 `d8a5222828c3adab70adf69a5583f1d32eb5ece04304f7f8392b6a353aa2228c`
and SHA-512 `d7a1d70a58b7d34ddd01a91d3ccbc086a36626b7081cfcbb150d24288c6adad612b042ba7ea63a218595afb2ee04384c0f8ba84ee3c6bd29913724b54e898d83`.
Both hashes are checked at build time. The upstream `COPYING` is retained under
`/usr/share/licenses/libxdmcp`; its SPDX identifier is `MIT-open-group`.

After building xorgproto, run `bash recipes/libxdmcp/build.sh` from the Linux
checkout. The output is `build/system-packages/libxdmcp-1.1.5.nspkg`.
