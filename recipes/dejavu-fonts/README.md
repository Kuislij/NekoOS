# DejaVu fonts

`build.sh` packages the official prebuilt TrueType release 2.37 as an NSPKG.
The archive and SHA-256 checksum are published on the
[DejaVu download page](https://dejavu-fonts.github.io/Download.html).
The script verifies the archive, installs all 22 TTF files below
`/usr/share/fonts/truetype/dejavu/`, and includes the upstream `LICENSE`.

This adds scalable Latin, Cyrillic, Greek, math, and other glyphs for the
NekoOS graphical desktop. Fontconfig scans `/usr/share/fonts`; no host fonts
are copied into the image.
