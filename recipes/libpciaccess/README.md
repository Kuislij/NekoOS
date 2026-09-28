# libpciaccess 0.19

This recipe cross-builds X.Org's generic PCI access library with its Linux
sysfs backend for the NekoOS musl runtime. The `NSPKG/1` archive includes
`libpciaccess.so.0`, the public header, `pciaccess.pc`, and the upstream
`COPYING` notices. It does not copy host distribution libraries.

The [X.Org release announcement](https://www.mail-archive.com/xorg-announce@lists.x.org/msg01883.html)
publishes the [source archive](https://xorg.freedesktop.org/archive/individual/lib/libpciaccess-0.19.tar.xz)
and both hashes, which are checked before extraction:

- SHA-256: `3c55aa86c82e54a4e3109786f0463530d53b36b6d1cfd14616454f985dd2aa43`
- SHA-512: `a20ea0ef3d650e2cdc18423ea4770780ce273c35115eece85dbbb59e5f2e24bdbaf88e53b1648f2c5d4fa34b015a3fe8318721bf5655a86a835db323e6ecd4f7`

After building the NekoOS musl toolchain, run
`bash recipes/libpciaccess/build.sh` inside the Linux checkout. The output is
`build/system-packages/libpciaccess-0.19.nspkg`.

Optional zlib support for compressed `pci.ids` is disabled until target zlib
is packaged. PCI enumeration still uses Linux sysfs; device name lookup needs
an optional plaintext `/usr/share/hwdata/pci.ids` file. The package metadata
uses `NOASSERTION` for the collection of permissive upstream notices, which
is preserved under `/usr/share/licenses/libpciaccess`.
