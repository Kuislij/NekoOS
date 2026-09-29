# libpng 1.6.58

This recipe builds the PNG reference library from the [official libpng
release](https://www.libpng.org/pub/png/libpng.html) using the NekoOS musl
compiler and packaged zlib 1.3.2. The upstream SHA-256 checksum is
`28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775`.
It is checked before extraction.

The NSPKG contains the shared `libpng16.so.16` library, public headers,
pkg-config metadata, and the upstream PNG Reference Library License version 2.
The recipe also runs a real RGBA PNG write/read round trip through the staged
musl loader and zlib package.
