# xorgproto 2025.1

This recipe builds the upstream X.Org protocol headers for the NekoOS X11
stack. It installs headers under `/usr/include/X11` and `/usr/include/GL`,
pkg-config descriptors under `/usr/share/pkgconfig`, and upstream license
notices under `/usr/share/licenses/xorgproto`. It contains no executable or
host-distribution libraries. These headers enable later X11 libraries; they do
not start a graphical session by themselves.

The source is the official
[`xorgproto-2025.1.tar.xz`](https://xorg.freedesktop.org/releases/individual/proto/xorgproto-2025.1.tar.xz).
The [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01858.html)
publishes both checksums, independently matched against the downloaded archive:

- SHA-256: `56898c716c0578df8a2d828c9c3e5c528277705c0484381a81960fe1a67668e8`
- SHA-512: `dbbee3aa1bc62721d64309e1d98807d403609d8129944b2e23e48f95d30c6448718c2842362994d67647908645bafc757c710070c5dcdca96d191fd2689d023a`

Upstream Meson declares MIT. Individual protocol and GL headers include their
own notices; the recipe copies every upstream `COPYING-*` file so the package
retains the full license text, including the SGI GL notice. The NSPKG metadata
uses the upstream project license identifier `MIT`.

The build uses the same pinned Meson 1.10.1 host-tool source and SHA-256 as
the Pixman recipe. It configures for NekoOS's musl x86-64 compiler and copies
only source-built protocol files into its staging tree. After the toolchain is
available, run `bash recipes/xorgproto/build.sh` in the Linux checkout. The
result is `build/system-packages/xorgproto-2025.1.nspkg` and the inspectable
staging tree at `build/system-package-build/xorgproto-2025.1/stage`.
