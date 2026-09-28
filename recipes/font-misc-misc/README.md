# font-misc-misc 1.1.3

This data-only recipe packages the upstream X.Org `6x13` and `9x15` Unicode
bitmap fonts for NekoOS's first X server. Both begin as unmodified BDF files from
the [official archive](https://xorg.freedesktop.org/archive/individual/font/font-misc-misc-1.1.3.tar.xz).
The [X.Org announcement](https://lists.x.org/archives/xorg-announce/2023-February/003363.html)
publishes these checksums; both are verified before extraction:

- SHA-256: `79abe361f58bb21ade9f565898e486300ce1cc621d5285bec26e14b6a8618fed`
- SHA-512: `fac4bfda0e4189d1a9999abc47bdd404f2beeec5301da190d92afc2176cd344789b7223c1b2f4748bd0efe1b9a81fa7f13f7037015d5d800480fa2236f369b48`

The pinned, source-built [bdftopcf](../bdftopcf/README.md) converts them to PCF
on the build host. The package places the PCF fonts in
`/usr/share/fonts/X11/misc` and generates a `fonts.dir` index from their XLFD
names. `fonts.alias` maps the common `fixed` name to `6x13`. Xorg uses this
directory in its font path. The converter itself does not enter the guest.
This limited set omits the other sizes and encodings in the upstream archive.

Run `bash recipes/font-misc-misc/build.sh` in the Linux checkout. The result
is `build/system-packages/font-misc-misc-1.1.3.nspkg`. The upstream `COPYING`
declares these fonts public domain and is included in the package; package
metadata uses `NOASSERTION` because public domain is not a precise SPDX
license expression.
