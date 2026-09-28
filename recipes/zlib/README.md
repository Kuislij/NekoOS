# zlib 1.3.2

This recipe builds zlib with the NekoOS musl toolchain for X.Org font libraries.
The NSPKG/1 package contains `libz.so.1`, headers, pkg-config metadata, and the
upstream license. It does not use the host distribution's zlib binary.

Source and published SHA-256:
[zlib 1.3.2](https://zlib.net/) (`d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3`
for the `.tar.xz` archive). The build checks this digest before unpacking.

Run `bash recipes/zlib/build.sh` from the Linux checkout after preparing the
musl toolchain. The output is `build/system-packages/zlib-1.3.2.nspkg`.
