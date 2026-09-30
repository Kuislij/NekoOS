# GTK3 3.24.52

This recipe supplies GTK3/GDK shared libraries, headers, pkg-config metadata,
settings schemas and toolkit utilities for NekoOS's software X11 session.
It builds from the [official GNOME release archive](https://download.gnome.org/sources/gtk/3.24/gtk-3.24.52.tar.xz),
pinned to SHA-256
`80931fa472a77b9a164f6740e3c0b444fac6770054632d35a7ff9d679e5e7b9f`.
The upstream LGPL-2.1-or-later notice is preserved at
`/usr/share/licenses/gtk3/COPYING`.

Build with `bash recipes/gtk3/build.sh` in the Linux checkout after the musl
toolchain, pinned Meson/pkgconf and all listed prerequisite NSPKG packages
are available. The output is `build/system-packages/gtk3-3.24.52.nspkg`.
Prerequisites are verified and installed into a separate sysroot. Compiler
flags and pkg-config searches resolve against those target packages;
Meson uses no fallback dependencies. Runtime directory variables keep the
guest's canonical `/usr`, while system settings use `/etc`. Guest ELF files
are checked for the musl interpreter, correct library SONAMEs and absence of
glibc dependencies, runtime search paths and absolute build paths.

The package includes the X11 backend and all supported built-in input method
modules. This avoids depending on an external input-module cache for basic
text entry. The recipe checks `gtk-query-immodules-3.0` using the packaged
musl runtime and compiles GTK's GSettings schemas explicitly, because the
staged installation does not run the normal post-install hooks. Cairo includes
the PDF/PostScript/SVG interfaces used by GTK's file print backend.

Host code generation uses `glib-genmarshal`, `glib-mkenums` and `gdbus-codegen`
from the hash-checked GLib 2.84.4 source. Resource and schema generation, and
GdkPixbuf pixel-data conversion, use the packaged guest utilities through the
pinned musl loader. Host-distribution GTK/GLib libraries are not copied into
the target. The Linux build host also needs Python, Ninja, binutils and msgfmt.

Wayland, Broadway, Windows/macOS backends, introspection, documentation,
demos, examples, upstream test programs, CUPS, cloud-provider integration,
Tracker and profiling are disabled. Libepoxy supplies GL dispatch interfaces;
NekoOS currently renders ordinary GTK widgets through Cairo in software and
does not include an OpenGL driver stack. The package supplies a toolkit;
Xfce's panel/session/desktop modules and Thunar remain subsequent work.

`neko-gtk-welcome` is a separate musl GTK3 application launched by
`neko-x11-session` under the `neko` user. It edits
`/home/neko/Documents/Neko-note.txt`, which is persistent when `/home` is
backed by the user data disk. `python3 tools/gtk_smoke.py` checks GTK widgets,
Cyrillic font layout, PNG decoding, Save/reload, visible write errors and UTF-8
notes across disposable initramfs and system-disk boots. Final image results
are recorded in [the GTK3 validation report](../../docs/validation-gtk3-2026-09-30.md).
