# GdkPixbuf 2.44.8

This recipe builds the GTK image-loading library and development files against
the pinned NekoOS musl, GLib 2.84.4 and libpng 1.6.58 packages. It installs
`libgdk_pixbuf-2.0.so.0`, C headers, pkg-config metadata, and the musl
`gdk-pixbuf-csource`, `gdk-pixbuf-pixdata` and `gdk-pixbuf-query-loaders` utilities.

The [official GNOME release archive](https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.8.tar.xz)
is checked against its [upstream SHA-256](https://download.gnome.org/sources/gdk-pixbuf/2.44/gdk-pixbuf-2.44.8.sha256sum):
`919f529512961a12e81cd4b4b466a48c3933469e7f9a310c6513cd4fb252ba3c`.
The upstream LGPL 2.1 license is preserved at
`/usr/share/licenses/gdk-pixbuf/COPYING`.

PNG and the legacy XPM API used by GTK are built directly into the shared
library. The shipped `loaders.cache` is a deterministic empty module cache;
neither loader depends on dynamic modules or staging-directory paths. JPEG,
TIFF, GIF, SVG/Glycin, thumbnailing, introspection, generated documentation and
GIO MIME sniffing are disabled. PNG files are recognized by their signatures.
Additional image formats can be packaged later with their required libraries.

The build uses isolated target pkg-config metadata, pinned Meson 1.10.1 and
pkgconf 2.5.1, and no fallback subprojects. The host enum/marshal generators
come from the verified GLib 2.84.4 source archive; they are not taken from the
host distribution. Resource generation uses a wrapper around the packaged
musl GLib utility. These build tools stay outside the guest package.

Run `bash recipes/gdk-pixbuf/build.sh` after the prerequisites. The output is
`build/system-packages/gdk-pixbuf-2.44.8.nspkg`. The recipe compiles and runs
`tests/gdk_pixbuf_runtime.c` through the staged musl loader while explicitly
pointing at a missing module cache. It verifies an RGBA PNG file round trip,
scaling, PNG buffer encoding/incremental decoding, and XPM transparency.
