# HarfBuzz

Pinned [HarfBuzz 12.3.0](https://github.com/harfbuzz/harfbuzz/releases/tag/12.3.0)
adds OpenType shaping, FreeType and GLib integration, GObject bindings and font
subsetting. The release asset SHA-256 is checked before extraction. Build with
`bash recipes/harfbuzz/build.sh` after the pinned musl, GLib, FreeType, DejaVu and
their prerequisites exist as NSPKG archives.

Upstream calls its main license "Old MIT"; the package retains that full
`COPYING` and the additional `src/ms-use/COPYING` notice. NSPKG metadata uses
`NOASSERTION` to avoid replacing legacy text with an inaccurate SPDX label.

The [upstream Meson option](https://github.com/harfbuzz/harfbuzz/blob/12.3.0/meson_options.txt)
`with_libstdcxx=false` selects the C linker; exceptions and RTTI are disabled by
upstream. A recipe-local wrapper runs the build-host GCC C++ frontend with its
matching C++ template headers and the existing musl specs. The GNU-libc-specific
libstdc++ OS configuration header is skipped, while C headers and the runtime
come from NekoOS musl. The build requires matching `gcc` and `g++` installations.
No host C library or C++ runtime is copied into the package. This extends the
existing host-GCC build model and is not a general guest C++ toolchain.

Every installed library is checked for musl SONAME dependencies, RPATH/build
paths, GNU libc, libstdc++, libgcc_s and unresolved C++ allocation/ABI/unwind
symbols. The staged runtime probe shapes Latin ligatures and Arabic using the
packaged DejaVu font and tests the GObject binding. Host `glib-mkenums` is extracted
from the separately hash-verified GLib 2.84.4 archive; it is not installed in the
guest. Optional ICU, Graphite, Cairo integration, tools, introspection and docs
are disabled.

The compiler startup objects' weak `__cxa_finalize` import is permitted, as it
is provided by musl and is also present in the existing C-only shared libraries.
Every other unresolved `__cxa*` symbol is rejected.
