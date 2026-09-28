# Xorg server 21.1.24

This recipe cross-builds a minimal X.Org X server for NekoOS musl. It includes
the Xorg executable, built-in DRM modesetting driver, and required server
modules. GLX, glamor, Mesa, nested servers, udev, and systemd integration are
disabled in this first software-rendered build. A working graphical session
still needs a DRM device, input handling, XKB layout data, fonts, and a window
manager or desktop applications; packaging the server alone does not start a
desktop.

Official source: [`xorg-server-21.1.24.tar.xz`](https://xorg.freedesktop.org/archive/individual/xserver/xorg-server-21.1.24.tar.xz).
The [X.Org release announcement](https://www.mail-archive.com/xorg@lists.x.org/msg08314.html)
publishes the hashes checked by the recipe:

- SHA-256: `1a4eb36ca65cc3b1b936566d677a9786e13c11cd5806e951ac55f3f5ce3984af`
- SHA-512: `f51372b04fe21632fc778ff240705161ed2dccc0114dbe3ee25156d8ac85ec945e2ac05d8638bc7d8d54bad4dfc89cb26b6bd2058b7804d54ab7179e1ac2eb13`

Build with `bash recipes/xorg-server/build.sh` in the Linux checkout after
building its verified NekoOS NSPKG/1 prerequisites. The output is
`build/system-packages/xorg-server-21.1.24.nspkg`. The build uses pinned Meson
1.10.1, pkgconf 2.5.1, musl GCC, and the separately packaged `libsha1` SHA-1
provider. The full upstream `COPYING` notice is installed in the package, so
metadata uses `NOASSERTION` for its multiple permissive notices.
