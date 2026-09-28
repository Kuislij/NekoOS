# libsha1 0.3

This recipe builds the small [upstream libsha1](https://github.com/dottedmag/libsha1)
SHA-1 provider for the NekoOS musl runtime. It is intended for X.Org server's
`-Dsha1=libsha1` build option. The package contains `libsha1.so.0`, the
development symlink `libsha1.so`, `libsha1.h`, and `libsha1.pc`.

Upstream tag [`0.3`](https://github.com/dottedmag/libsha1/tree/0.3) resolves
to commit `3f976bbb57d77f0c6964ecd5fbd3d99a2b9f65e5`. The recipe downloads
the [archive of that exact commit](https://codeload.github.com/dottedmag/libsha1/tar.gz/3f976bbb57d77f0c6964ecd5fbd3d99a2b9f65e5)
and checks these hashes measured from the upstream archive:

- SHA-256: `0ef7b0ead391ce5d1c99ab1d68bbc5128e18a60bfd1d245f9d760753889bec67`
- SHA-512: `9b982e83c2d4db9e0f66f4320fca4daf3be50d2eddb01df18880b6e8d27ec9d65dd7f7971784409a562c50e1d24f79edda1556cc5bfd17af80ad64564bb3098f`

The tag contains Autotools source files but no generated `configure` script.
The recipe directly compiles upstream `sha1.c` for x86_64 musl and writes the
pkg-config data described by upstream `libsha1.pc.in`. Its build checks the
shared library's SONAME and musl dependency, then runs the staged library
against the standard SHA-1 digest for `abc`.

After the NekoOS musl toolchain is built, run `bash recipes/libsha1/build.sh`
in the Linux checkout. The result is `build/system-packages/libsha1-0.3.nspkg`.
The full `COPYING` text, which offers a permissive license or GPL alternative,
is preserved under `/usr/share/licenses/libsha1`; metadata is `NOASSERTION`.
