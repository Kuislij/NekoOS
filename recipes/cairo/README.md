# Cairo 1.18.6

This recipe builds Cairo's shared musl libraries (`libcairo.so.2` and
`libcairo-gobject.so.2`), C headers and pkg-config metadata for NekoOS. It
enables image, PNG, PDF, PostScript, SVG, FreeType/Fontconfig, Xlib/Xrender and XCB surfaces.
This is the 2D drawing layer used by desktop applications; it does not
provide a window manager or a GTK widget toolkit by itself. Zlib support supplies
the compressed document streams needed by PDF and PostScript. CairoScript,
GL and Wayland backends, GTK 2 utilities, tests
and generated API documentation are disabled for this package.

The source is the [official Cairo 1.18.6 release](https://www.cairographics.org/news/cairo-1.18.6/)
with upstream SHA-256
`1c767308174337a74694da0f3ec069c271452163a1ef4540964c50c301f157d4`.
The package preserves the upstream dual-license notices in
`/usr/share/licenses/cairo/COPYING`, `COPYING-LGPL-2.1` and `COPYING-MPL-1.1`.
Because Cairo includes components under multiple terms, the NSPKG metadata
uses `NOASSERTION` rather than an incomplete SPDX expression.

The build stages the pinned NSPKGs for Pixman, libpng, zlib, FreeType, Fontconfig,
X11/XCB/Xrender and GLib/GObject, together with their transitive build
dependencies. Host-distribution libraries are excluded by the isolated
pkg-config search path and Meson's no-fallback mode. The host uses the pinned
Meson 1.10.1 and pkgconf 2.5.1 already prepared by their earlier recipes.

After the musl toolchain and prerequisites are built, run
`bash recipes/cairo/build.sh` in the Linux checkout. The output is
`build/system-packages/cairo-1.18.6.nspkg`. The recipe also compiles a small
musl program against the installed package, draws and rereads a PNG image,
initializes a Cairo-GObject type, and exports a small vector page to PDF. The PDF
probe finishes the surface, checks Cairo's status, verifies the document header
and final EOF trailer, and removes its temporary file. The PNG image is kept under
`build/system-package-build/cairo-1.18.6/smoke.png` for inspection.
