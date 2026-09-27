# xcb-proto (host-side build tool)

This recipe stages upstream xcb-proto 1.17.0 for building libxcb. It installs
the XCB protocol XML descriptions, `xcb-proto.pc`, and the Python `xcbgen`
module into `build/host-tools/xcb-proto-1.17.0/stage/usr`. These files run or
are read on the Linux build host; they are **not** included in the NekoOS guest
image or packaged as NSPKG.

Run `bash recipes/xcb-proto/build.sh` in the Linux NekoOS checkout. The source
is the [official X.Org xcb-proto 1.17.0 tarball](https://xorg.freedesktop.org/archive/individual/xcb/xcb-proto-1.17.0.tar.xz),
verified against SHA-256
`2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c`.

The recipe prints the exact `PKG_CONFIG_PATH`, `PYTHONPATH`, and
`XCBPROTO_XCBINCLUDEDIR` for libxcb. Its generated
`build/host-tools/xcb-proto-1.17.0/env.sh` can also be sourced before libxcb's
configure step. A staged prefix is used so the installed `.pc` file resolves
its `xcbincludedir` and `pythondir` to host paths rather than guest paths.
