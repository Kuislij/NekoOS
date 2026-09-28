# xf86-input-evdev 2.11.0

This recipe cross-builds the X.Org evdev input module for NekoOS musl. It
provides `evdev_drv.so` for explicitly configured `/dev/input/event*` devices.
The NekoOS Xorg build currently has no udev hotplugging, so devices need an
Xorg configuration entry that names their event node.

Official source: [`xf86-input-evdev-2.11.0.tar.xz`](https://xorg.freedesktop.org/archive/individual/driver/xf86-input-evdev-2.11.0.tar.xz).
The [X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg07808.html)
publishes the hashes checked by the recipe:

- SHA-256: `730022de934cc366bb12439daf202a7bfff52a028cf4573e457642e25a071315`
- SHA-512: `ccd3727d9726565259a81db1c238aba7e414292c3f91e182c048845ac3caf1705c2b16ff1775f3b35ecb3b7088903257085bc90a20265641ccde05b2fc6966df`

The release tarball includes a generated Autotools `configure` script. Its
libudev pkg-config probe is treated as mandatory, though the driver source
supports building without libudev. NekoOS disables udev in Xorg, so the
recipe removes precisely that probe from the extracted generated script and
leaves `HAVE_LIBUDEV` undefined. This avoids a libudev runtime requirement;
all other upstream source and build checks remain intact.

Build with `bash recipes/xf86-input-evdev/build.sh` in the Linux checkout
after building the verified Xorg, libevdev, and mtdev packages. The output is
`build/system-packages/xf86-input-evdev-2.11.0.nspkg`. The upstream `COPYING`
file is included in full; metadata uses `NOASSERTION` for its distinct
permissive notices.
