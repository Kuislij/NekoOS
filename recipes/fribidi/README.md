# FriBidi

Pinned [FriBidi 1.0.16](https://github.com/fribidi/fribidi/releases/tag/v1.0.16)
provides the Unicode bidirectional algorithm used by Pango for mixed left-to-right
and right-to-left text. The shared library, headers and pkg-config metadata are
built against NekoOS musl in an isolated empty sysroot. Native source table
generators are build-host tools only. Optional binaries, docs and upstream tests
are disabled. `smoke.c` checks actual Hebrew reordering and index mappings using
the staged musl loader.

Build with `bash recipes/fribidi/build.sh` after building the musl toolchain and
pinned host Meson/pkgconf. The release archive SHA-256 is checked before use.
