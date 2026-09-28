# libffi 3.5.2

This recipe builds libffi for the NekoOS musl toolchain. The shared library,
headers and `libffi.pc` are a prerequisite for GObject and the GTK/Xfce stack.
The source is the [official libffi release](https://github.com/libffi/libffi/releases/tag/v3.5.2).
Both checksums of its release tarball are verified before extraction:

- SHA-256: `f3a3082a23b37c293a4fcd1053147b371f2ff91fa7ea1b2a52e335676bac82dc`
- SHA-512: `76974a84e3aee6bbd646a6da2e641825ae0b791ca6efdc479b2d4cbcd3ad607df59cffcf5031ad5bd30822961a8c6de164ac8ae379d1804acd388b1975cdbf4d`

The release archive already contains `configure`. It is built as a shared
musl library without host-distribution libraries and packaged as
`build/system-packages/libffi-3.5.2.nspkg`. The upstream `LICENSE` is kept
inside the package.
