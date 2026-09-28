# mtdev 1.1.7

This recipe cross-builds Henrik Rydberg's multitouch event translation
library for NekoOS musl. It converts Linux multitouch events to the slotted
protocol expected by X.Org input drivers. The package includes
`libmtdev.so.1`, public headers, `mtdev.pc`, and the guest `mtdev-test`
utility. It does not use the host distribution's shared library.

The [upstream release page](https://bitmath.se/org/code/mtdev/) lists version
1.1.7 and its [source archive](https://bitmath.se/org/code/mtdev/mtdev-1.1.7.tar.bz2).
These hashes were measured from that official archive and are checked before
extraction:

- SHA-256: `a107adad2101fecac54ac7f9f0e0a0dd155d954193da55c2340c97f2ff1d814e`
- SHA-512: `e6174a38cf67a7f12a3b91e4e27bf74a18d6b40a956950ebb748b0ff87092333daa07e647b26038a5a533f8c48e845d649848e6ba99ea009ab87fd96ed188152`

After preparing the NekoOS musl toolchain, run `bash recipes/mtdev/build.sh`
in the Linux checkout. The result is `build/system-packages/mtdev-1.1.7.nspkg`.
The recipe verifies the musl runtime dependency, SONAME and executable
interpreter. The upstream [MIT/X11 license](https://bitmath.se/org/code/mtdev/)
is included under `/usr/share/licenses/mtdev/COPYING`.
