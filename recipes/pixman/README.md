# pixman 0.46.4

Pixman is the MIT-licensed pixel compositing library used by the X server and
Cairo. This recipe builds its shared library, headers and pkg-config metadata
against NekoOS's pinned musl toolchain. It is a dependency of the planned
Xorg/Xfce desktop, not a desktop session by itself.

Upstream release: <https://cairographics.org/releases/pixman-0.46.4.tar.gz>.
SHA-256: `d09c44ebc3bd5bee7021c79f922fe8fb2fb57f7320f55e97ff9914d2346a591c`.
The recipe also checks the SHA-512 published in upstream's
[`pixman-0.46.4.tar.gz.sha512`](https://cairographics.org/releases/pixman-0.46.4.tar.gz.sha512).
License: MIT; the upstream `COPYING` is installed in the package.
Runtime dependency: the musl libc already present in the NekoOS base image.

The host build tool is the pinned official Meson 1.10.1 source release:
<https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz>,
SHA-256 `c42296f12db316a4515b9375a5df330f2e751ccdd4f608430d41d7d6210e4317`.
It is run from `build/host-tools` without installing anything into the host
system. Python 3, Ninja, GCC, binutils and the existing NekoOS musl toolchain
are needed on the build host. Tests and demo programs are disabled so the
package has no GTK, libpng or OpenMP dependency.

After the musl toolchain is available, run `bash recipes/pixman/build.sh` in
the Linux checkout. It writes `build/system-packages/pixman-0.46.4.nspkg`
using `tools/system_package.py` and stages the installed files under
`build/system-package-build/pixman-0.46.4/stage` for inspection.
