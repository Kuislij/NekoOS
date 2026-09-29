# PCRE2 10.48

This recipe builds the 8-, 16-, and 32-bit PCRE2 shared libraries, the POSIX
wrapper, headers, `pcre2-config`, and pkg-config metadata with the pinned NekoOS
musl toolchain. The 8-bit library is a prerequisite for a future GLib package.
Unicode and x86-64 JIT support are enabled. The resulting package contains no
host-distribution libraries.

Source: [official PCRE2 10.48 release](https://github.com/PCRE2Project/pcre2/releases/tag/pcre2-10.48),
`pcre2-10.48.tar.gz`. Its SHA-256
`ebcc25aadf2a51fa1fefa9b8bc9e7a79b3dae86870a0f1152a22e42befd46888`
is published in the [upstream release attestation](https://github.com/PCRE2Project/pcre2/attestations/44153304).
The recipe also verifies SHA-512
`7682828c8bf512406f3f1bff773830416e55750bec1cf4bb39a1238f5a61026df71817dbd2dd0fcd72a76fcfb15d7b386a64739b33ad99bad77170652248fa35`
before extraction.

Run `bash recipes/pcre2/build.sh` in the Linux checkout after building the
musl toolchain. The output is `build/system-packages/pcre2-10.48.nspkg`.
The package preserves upstream `LICENCE.md` (BSD-3-Clause with PCRE2 exception)
and the separate JIT compiler license under `/usr/share/licenses/pcre2/`.
