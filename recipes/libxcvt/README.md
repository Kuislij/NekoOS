# libxcvt 0.1.3

This recipe cross-builds X.Org's VESA CVT mode timing library and `cvt`
utility against the NekoOS musl toolchain. The resulting `NSPKG/1` archive
contains `libxcvt.so.0`, public headers, `libxcvt.pc`, `/usr/bin/cvt`, and the
upstream `COPYING` notices. The host's X.Org libraries are never copied into
the guest package.

The [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01780.html)
publishes the [source archive](https://xorg.freedesktop.org/archive/individual/lib/libxcvt-0.1.3.tar.xz)
and both hashes, which are checked before extraction:

- SHA-256: `a929998a8767de7dfa36d6da4751cdbeef34ed630714f2f4a767b351f2442e01`
- SHA-512: `2fecc784375e69b6e8e46608618a5f5a8ad20ecd5229fd093883fe401dd6ea231d8b77c6753756fff01f3040bef2db60a042d40fc349769ef5348e5cd9ed1f28`

After building the NekoOS musl toolchain, run `bash recipes/libxcvt/build.sh`
inside the Linux checkout. The output is
`build/system-packages/libxcvt-0.1.3.nspkg`. The recipe verifies the library
SONAME, musl linkage, and the executable interpreter. Multiple permissive
notices appear in `COPYING`, so the package metadata uses `NOASSERTION` while
preserving the full upstream text under `/usr/share/licenses/libxcvt`.
