# libXau 1.0.12

libXau supplies X11 authority-file handling for the eventual Xorg desktop.
This recipe builds its shared library, public header, and `xau.pc` against
NekoOS's pinned musl toolchain. It requires the separately packaged
`xorgproto-2025.1` headers and does not install anything into the host OS.

Upstream archive: <https://xorg.freedesktop.org/archive/individual/lib/libXau-1.0.12.tar.xz>.
The official [X.Org release announcement](https://lists.x.org/archives/xorg-announce/2024-December/003570.html)
publishes SHA-256 `74d0e4dfa3d39ad8939e99bda37f5967aba528211076828464d2777d477fc0fb`
and SHA-512 `4bbe8796f4a14340499d5f75046955905531ea2948944dfc3d6069f8b86c1710042bfc7918d459320557883e6631359d48e6173c69c62ff572314e864ff97c5e`.
Both hashes are checked at build time. The upstream `COPYING` is retained under
`/usr/share/licenses/libxau`; its SPDX identifier is `MIT-open-group`.

After building xorgproto, run `bash recipes/libxau/build.sh` from the Linux
checkout. The output is `build/system-packages/libxau-1.0.12.nspkg`.
