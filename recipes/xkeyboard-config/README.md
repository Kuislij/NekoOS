# xkeyboard-config 2.48

This recipe builds the X.Org keyboard rules and layout data for NekoOS. It
packages the generated `rules/evdev` files, keycodes, symbols, geometry,
compatibility maps and types under `/usr/share/xkeyboard-config-2`. The
traditional `/usr/share/X11/xkb` path is a relative symlink to that versioned
tree. `xkeyboard-config-2.pc` describes the installed paths.

The [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01915.html)
publishes the [source archive](https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config/xkeyboard-config-2.48.tar.xz)
and both hashes, checked before extraction:

- SHA-256: `b77041324f0109f77161ee43743fe04baa485866af8460d31e476ad3f7648fd5`
- SHA-512: `2c24f9cca97b8863ff2e71fc3780e9c3e22e4486c80d45022e2208d559bdb40824bdb8a4037e0d5690900b6e080ddef4eacfc8bff843e04ba5ab86940f1fb6ea`

Build with `bash recipes/xkeyboard-config/build.sh` in the Linux checkout.
The output is `build/system-packages/xkeyboard-config-2.48.nspkg`. Host Python,
Perl, Meson and Ninja generate the data; the package contains no host ELF
runtime files. Native-language catalogues are disabled for this foundation
package, while US and Russian layouts and compatibility rules are included.
The complete upstream `COPYING` with multiple permissive notices is installed
under `/usr/share/licenses/xkeyboard-config`; package metadata is
`NOASSERTION` until those notices are represented precisely.
