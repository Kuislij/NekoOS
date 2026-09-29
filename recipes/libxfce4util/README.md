# libxfce4util 4.20.1

This recipe builds the first Xfce 4.20 library for NekoOS from the
[official release archive](https://archive.xfce.org/src/xfce/libxfce4util/4.20/).
It uses the packaged GLib 2.84.4 headers and libraries, the NekoOS musl
compiler and host pkgconf. The source archive is checked with SHA-256 and
SHA-512 before extraction.

- SHA-256: `84bfc4daab9e466193540c3665eee42b2cf4d24e3f38fc3e8d1e0a2bebe3b8f1`
- SHA-512: `b9eecac47245c37a46f8e381ed5c672233aae3a78cae8ac0b25a79598847210267172cd03d64d5f4d0405640608f4885092fd62431914b58a930c7b401067268`

The package contains `libxfce4util.so.7`, its headers,
`libxfce4util-1.0.pc` and `xfce4-kiosk-query`. GObject Introspection, Vala,
documentation and translations are disabled because their build-time
generators are not yet packaged for this cross-build. The archive contains
both Library GPL and GPL licensed code, so the package metadata uses
`NOASSERTION` and preserves the upstream `COPYING` file.
