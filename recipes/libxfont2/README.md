# libXfont2 2.0.9

This recipe builds X.Org's server-side font library for NekoOS musl. It uses
only verified NekoOS xorgproto, xtrans, zlib and libfontenc packages. The
[X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg08332.html)
publishes the [archive](https://xorg.freedesktop.org/archive/individual/lib/libXfont2-2.0.9.tar.xz)
and its checksums, both verified before extraction:

- SHA-256: `f042a370666815e7b941e9b7019024755bd1c6c2954afbfa515af378251799e2`
- SHA-512: `ccd6d6abf6aa814a940d137813dba638f8259c3672abf00808d82df033c1026ae29d40c9068da4f112637338ad0d0fc15818a4afa9369a626c8f17e466b4fa72`

Upstream's `README.md` says gzip/zlib support is mandatory. This first NekoOS
build enables built-in, PCF and BDF bitmap fonts, including gzip-compressed
fonts. It disables FreeType scalable fonts, bzip2-compressed fonts and remote
font servers. Those features need their own verified dependencies or are not
needed for the first local Xorg milestone. Built-in `fixed` and `cursor` fonts
remain available to the X server.

After building `libfontenc-1.1.9.nspkg`, run
`bash recipes/libxfont2/build.sh` in the Linux checkout. The result is
`build/system-packages/libxfont2-2.0.9.nspkg` with `libXfont2.so.2`, the public
header, `xfont2.pc` and upstream `COPYING`. The mixed permissive notices in
`COPYING` are retained; package metadata uses `NOASSERTION` pending an exact
license expression.
