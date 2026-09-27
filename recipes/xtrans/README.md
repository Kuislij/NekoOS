# xtrans 1.6.0

xtrans provides the X.Org network transport implementation included directly
by consumers such as libX11. It contains C source fragments, headers,
`xtrans.pc`, and `xtrans.m4`; it is not a separately linked runtime library.
The recipe configures its build for NekoOS's musl toolchain and packages the
upstream `COPYING` notice under `/usr/share/licenses/xtrans`.
Because that file contains several distinct permissive notices, the package
metadata uses `NOASSERTION` until a precise expression is recorded.

The upstream archive is [xtrans-1.6.0.tar.xz](https://xorg.freedesktop.org/archive/individual/lib/xtrans-1.6.0.tar.xz).
The official [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01797.html)
publishes SHA-256 `faafea166bf2451a173d9d593352940ec6404145c5d1da5c213423ce4d359e92`
and SHA-512 `e0ac4a2df0eeacdf23cedd74fee063a8eea81d05c4c4c9a9a113b9b4238db7cacb3c831973ac647fe1a5b06426dcdf0b2f8be5ac27862700333269880e25725b`.
The recipe checks both before unpacking.

Run `bash recipes/xtrans/build.sh` from the Linux checkout after preparing the
musl toolchain. The output is `build/system-packages/xtrans-1.6.0.nspkg`.
