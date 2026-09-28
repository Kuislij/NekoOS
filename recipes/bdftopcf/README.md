# bdftopcf 1.1.2 (build host only)

NekoOS builds [X.Org bdftopcf 1.1.2](https://xorg.freedesktop.org/archive/individual/util/bdftopcf-1.1.2.tar.xz) from a pinned source archive and checks both SHA-256 and SHA-512. It uses the packaged X.Org protocol headers and the pinned host pkgconf.

This tool converts verified upstream BDF bitmap fonts into PCF files while assembling the NekoOS image. The tool itself is not installed in the guest. Its upstream license notice remains in the verified source archive.
