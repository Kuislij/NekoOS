# FreeType 2.14.3

This recipe builds the font engine from the [official FreeType release](https://freetype.org/download)
with the NekoOS musl compiler. It links against packaged zlib 1.3.2 for
gzip-compressed fonts. Bzip2, PNG, Brotli and HarfBuzz support are deferred
until those libraries are packaged. The archive hashes are checked before
extraction; the SHA-256 value is published in the [2.14.3 release listing](https://sourceforge.net/projects/freetype/files/freetype2/2.14.3/).

- SHA-256: `36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f`
- SHA-512: `43de86ea70b4b47f6efaae67f3440f65a24ffac29dc6d11203a9764e4f1a749ce1ba7645acd23525220b3ba12ddad8687b962b9f1254e2c0a86070854e85d5a0`

The package contains `libfreetype.so.6`, the public headers and
`freetype2.pc`. FreeType offers a choice between the FreeType License and
GPLv2 or later; package metadata uses `NOASSERTION` and preserves both full
license texts plus the top-level license notice.
