# D-Bus 1.16.2

This recipe builds the reference D-Bus session daemon, low-level `libdbus-1`
shared library, headers, pkg-config metadata, configuration, and command-line
tools for NekoOS musl. It uses the packaged Expat 2.8.5 XML parser and the
pinned host-only Meson 1.10.1 and pkgconf 2.5.1. Systemd, AppArmor, SELinux,
X11 autolaunch, documentation, and installed regression tests are disabled.
The package is configured for a per-user session bus; system-bus configuration
and its privileged activation helper are omitted.

Source: [official D-Bus 1.16.2 archive](https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz).
The upstream [SHA-256 file](https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz.sha256sum)
publishes `0ba2a1a4b16afe7bceb2c07e9ce99a8c2c3508e5dec290dbb643384bd6beb7e2`.
The recipe also verifies SHA-512
`5c26f52d85984bb9ae1dde8d7e73921eacbdf020a61ff15f00a4c240cb38a121553ee04bd66e62b28425ff9bc50f4f5e15135166573ac0888332a01a0db1faa2`.

Run `bash recipes/dbus/build.sh` in the Linux checkout after building the Expat
package. It writes `build/system-packages/dbus-1.16.2.nspkg` with an explicit
`expat>=2.8.5` dependency. The package includes `dbus-daemon --session`,
`/usr/share/dbus-1/session.conf`, and the upstream license texts. Session
applications should start the daemon with `dbus-run-session` or export the
address printed by `dbus-daemon --session --print-address`. Run
`bash recipes/dbus/smoke.sh` in the WSL checkout to check that the staged
`dbus-run-session` launches a temporary bus that answers a `gdbus` call. When
the GLib package has been built, this check also uses its packaged musl
`gdbus` executable; before then, it uses the build host's client.
