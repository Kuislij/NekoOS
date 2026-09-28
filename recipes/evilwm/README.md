# evilwm 1.5

NekoOS builds [evilwm 1.5](https://www.6809.org.uk/evilwm/) from its upstream
source archive as the first X11 window manager. It manages and reparents normal
application windows, supports mouse and keyboard window controls, and uses
RandR for monitor geometry. It is an intermediate graphical-session component;
the intended full desktop remains Xfce with Thunar.

The recipe verifies the upstream archive with pinned hashes before compiling
against NekoOS's musl, libX11, libXext, and libXrandr packages:

- [Upstream archive](https://www.6809.org.uk/evilwm/dl/evilwm-1.5.tar.gz)
- SHA-256: `6104852413e6d50669361dcadda5a25d39e2b2b0c95a6384022c905957a2740f`
- SHA-512: `91495841ec78d350253553c7970fe93097c6634f80d13c30a1e0329d82ab53b131ab1b7946b29837b191c4d450567bd3f3f4387ace0280f969fe14a874d5d304`

The complete upstream redistribution notice is installed under
`/usr/share/licenses/evilwm/README`; package metadata uses `NOASSERTION`
because it includes the historical aewm and 9wm terms. The
[upstream build guide](https://www.6809.org.uk/evilwm/build.shtml) identifies
X11 and RandR as its development dependencies. This package enables RandR and
Shape support already present in the upstream Makefile.
