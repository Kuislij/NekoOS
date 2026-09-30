# Pango

Pinned [Pango 1.56.4](https://download.gnome.org/sources/pango/1.56/) provides
Unicode layout, shaping through HarfBuzz, bidirectional ordering through FriBidi
and rendering through the Cairo/FreeType/Fontconfig backend used by GTK3. The
upstream published SHA-256 is checked before use. Build with
`bash recipes/pango/build.sh` after its declared NSPKG prerequisites exist.

Upstream Meson declares LGPLv2.1+, while the distributed `COPYING` contains the
GNU Library GPL version 2 text. The package retains that exact notice and uses
`NOASSERTION` for NSPKG license metadata.

All dependency headers, libraries and pkg-config metadata come from verified
NSPKG archives installed into a private musl sysroot. Host `glib-mkenums` is
extracted from the separately hash-verified GLib archive, with no dependency on
a previous GLib build directory. Linux Pango uses C; GCC serves the upstream
Windows-only C++ compiler declaration without linking a C++ runtime. Libraries,
development headers, pkg-config metadata and `pango-view` are shipped. Xft,
libthai, introspection, docs, upstream tests and examples are disabled; Thai
dictionary word segmentation is therefore not included in this initial build.

The recipe rejects GNU-libc/C++ runtime dependencies, RPATH and build paths in
every shipped ELF. Its musl runtime probe lays out Latin, Russian, Hebrew and
Arabic using packaged DejaVu fonts, verifies no unknown glyphs, renders a PNG
and checks that pixels were actually painted. Fontconfig is pointed only at the
private package sysroot for that probe.
