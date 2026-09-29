# Expat 2.8.5

This recipe builds the Expat XML parser shared library, its three public headers,
`expat.pc`, and CMake metadata against the pinned NekoOS musl toolchain. Expat is a prerequisite
for future fontconfig and D-Bus packages. The guest package excludes the host
`xmlwf` utility, examples, tests, static archive, and documentation. No host
distribution library is linked into `libexpat.so.1`.

Source: [official Expat 2.8.5 release](https://github.com/libexpat/libexpat/releases/tag/R_2_8_5),
`expat-2.8.5.tar.xz`. The SHA-256
`1e727b8933ec51a77a9a9d9afcf8e688bce45d907c13e36ab7393fe36e703182`
is the asset digest in the [upstream Releases API](https://api.github.com/repos/libexpat/libexpat/releases/tags/R_2_8_5).
The recipe also verifies SHA-512
`ad3d4198a70682c7c8b2149cb7c743585cc9470ea2e4bd81ec7c0aff9545d9010b51df5cfcd0714335c7ef1578537cbd2a5580f649246b4ea78ee5e3466808a3`.

Run `bash recipes/expat/build.sh` in the Linux checkout after building the musl
toolchain. The recipe runs a musl-linked XML parse test with the staged library,
then writes `build/system-packages/expat-2.8.5.nspkg`. Upstream's MIT license is
installed as `/usr/share/licenses/expat/COPYING`.
