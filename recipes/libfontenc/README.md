# libfontenc 1.1.9

This recipe builds X.Org's font encoding library for NekoOS musl from the
upstream source archive. It uses the verified NekoOS xorgproto and zlib system
packages; no host-distribution headers or libraries are copied into the guest.
The release archive already contains its generated `configure` script, so
X.Org font-util macros are not needed on the build host.

The [X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg08251.html)
publishes the [archive](https://xorg.freedesktop.org/archive/individual/lib/libfontenc-1.1.9.tar.xz)
and both checksums, verified before extraction:

- SHA-256: `9d8392705cb10803d5fe1d27d236cbab3f664e26841ce01916bbbe430cf273e2`
- SHA-512: `19050c4c9ea1143b555b92faec641fd6b4976de463ad1fb67d20a7bf2f610bbc3debd3c65925cd8329691a9fb0435d004a05b6486e1dc600719e8c479812b912`

Upstream requires zlib to read compressed encoding files; this cannot be
disabled in its standard build. After building `zlib-1.3.2.nspkg`, run
`bash recipes/libfontenc/build.sh` in the Linux checkout. The result is
`build/system-packages/libfontenc-1.1.9.nspkg`, containing `libfontenc.so.1`,
headers, `fontenc.pc` and upstream `COPYING`. The mixed permissive notices in
`COPYING` are retained; package metadata uses `NOASSERTION` pending an exact
license expression.
