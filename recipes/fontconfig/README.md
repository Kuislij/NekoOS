# Fontconfig 2.17.1

This recipe builds Fontconfig's shared musl library, C headers, pkg-config
metadata and guest tools (`fc-match`, `fc-list`, `fc-cache` and companions).
It requires the `expat-2.8.5` and `freetype-2.14.3` system packages. zlib is
also staged to satisfy FreeType's dependency. The package installs its
configuration under `/usr/etc/fonts` because NSPKG owns only `/usr`. It scans
`/usr/share/fonts`, enables bitmap fonts, and uses `/var/cache/fontconfig`
plus each user's cache at runtime. Font files are packaged separately.

The source is the [official Fontconfig 2.17.1 release](https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.17.1/fontconfig-2.17.1.tar.xz).
The upstream SHA-256 sum is
`9f5cae93f4fffc1fbc05ae99cdfc708cd60dfd6612ffc0512827025c026fa541`.
The recipe additionally verifies SHA-512
`c09c1f041f61ee0d220ff906a86b5c4b329106dc96f8c04b23f8fdeb480df626717fe3613bccb41cb39e86334078139322710377f5ddaa3abe48569e798161c9`.
All upstream notices are retained in `/usr/share/licenses/fontconfig/COPYING`.

The build requires GNU gperf, so it prepares a host-only copy of
[gperf 3.3](https://ftp.gnu.org/gnu/gperf/gperf-3.3.tar.gz) from its
[published SHA-256](https://lists.gnu.org/archive/html/info-gnu/2025-04/msg00013.html)
`fd87e0aba7e43ae054837afd6cd4db03a3f2693deb3619085e6ed9d8d9604ad8`.
That host executable is not installed in the guest package. Run
`bash recipes/fontconfig/build.sh` in the Linux checkout; the output is
`build/system-packages/fontconfig-2.17.1.nspkg`.

Run `bash recipes/fontconfig/smoke.sh` after building the Fontconfig and
`font-misc-misc` packages. It installs their NSPKGs and required libraries
into an isolated test root, then uses the packaged musl `fc-list` and
`fc-match` executables to verify both PCF fonts and the `fixed` alias.
