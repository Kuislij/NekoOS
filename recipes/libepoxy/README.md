# Libepoxy for GTK 3

Libepoxy 1.5.10 is built from the hash-pinned
[official GNOME archive](https://download.gnome.org/sources/libepoxy/1.5/).
The shared musl library includes the OpenGL and GLX dispatch interfaces required
by GTK's X11 backend. EGL, documentation and upstream GL-context tests are disabled.

This package supplies a dispatch library, not an OpenGL driver. NekoOS currently
uses GTK's software drawing path; GL applications will need a separate driver
stack. The recipe resolves X11 headers from NekoOS packages, rejects glibc/RPATH
leaks and includes the upstream MIT license. GTK guest tests verify its use in the
complete toolkit.

Build after the X11 packages with `bash recipes/libepoxy/build.sh`.
