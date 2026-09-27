# libXext 1.3.7

This recipe builds X.Org's library for common X11 extensions against NekoOS
musl and the verified NekoOS Xlib package. It installs `libXext.so.6`, public
headers, `xext.pc` and the upstream `COPYING` notice into an `NSPKG/1` system
archive. Build prerequisites are the NekoOS X11 protocol, transport, XCB and
Xlib packages; none are copied from the host distribution.

The official [X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg08238.html)
publishes the [source archive](https://xorg.freedesktop.org/archive/individual/lib/libXext-1.3.7.tar.xz)
and its checksums, both verified before extraction:

- SHA-256: `6c643c7035cdacf67afd68f25d01b90ef889d546c9fcd7c0adf7c2cf91e3a32d`
- SHA-512: `09cd230da472e87e4fdbc9b0f83a9181cc44af04c06fa4a7d8aa405e0f8551d3ac3a4b379249c44d97e1025b60d1c52f8ca13817eed0206e2bf3d66a55d89701`

The upstream `COPYING` contains several distinct permissive X.Org notices and
is staged under `/usr/share/licenses/libxext`. Package metadata uses
`NOASSERTION` until those notices are represented as a precise license
expression. After building libX11, run
`bash recipes/libxext/build.sh` in the Linux checkout. The result is
`build/system-packages/libxext-1.3.7.nspkg`.
The recipe maps source paths to a stable prefix and strips unneeded debug
symbols from the shared library before packaging.
