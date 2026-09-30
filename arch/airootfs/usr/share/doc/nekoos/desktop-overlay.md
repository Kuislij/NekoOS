# NekoOS Arch desktop overlay

This is a development VM profile using official Arch binary packages. It is
an Arch-derived distribution, with glibc, systemd and pacman, and a complete
Xfce session rather than the legacy musl image's minimal window manager.

The image builder installs `arch/packages.x86_64`, copies `arch/airootfs/.`
into the fresh root, and runs this command inside the target chroot:

```sh
/usr/local/lib/nekoos/setup-desktop.sh --development
```

Invoke it through Bash if the copy operation has not yet set executable modes.
The setup selects Russian UTF-8, also generates English UTF-8, enables
NetworkManager and LightDM, selects `graphical.target`, and prepares a normal
`neko` account. LightDM starts the official `xfce` session automatically. Xorg
uses its bundled modesetting driver and the packaged libinput driver; there is
no copied legacy evdev configuration. The keyboard layouts are `us,ru` with
Alt+Shift switching. Thunar opens the home folder at login. The packaged stock
Xfce panel configuration is copied for a new account, avoiding its first-run
configuration dialog. A small original SVG supplies the wallpaper.

This development VM deliberately has local autologin and the documented
`neko` / `neko` credentials. The serial console also logs in as `neko`, while
root's password is locked. Wheel membership grants normal password-checked
sudo access. It does not grant passwordless sudo. Change the account password
before using this image outside its local development setting. The setup
script is for a newly built image, not an updater for an existing home.

GRUB defaults provide NekoOS branding and both graphical and serial consoles.
The image builder is responsible for partitions, filesystem UUIDs, GRUB
installation and initramfs generation. Pacman retains Arch package ownership,
signatures, package metadata and upstream license files. `/etc/os-release` is
the NekoOS override; `/usr/lib/os-release` remains Arch's package-owned file.

Package selection and configuration references (checked 2026-09-30):

- [Official Arch Xfce group](https://archlinux.org/groups/x86_64/xfce4/)
- [Xfce on Arch](https://wiki.archlinux.org/title/Xfce)
- [LightDM autologin](https://wiki.archlinux.org/title/LightDM#Enabling_autologin)
- [Official LightDM files](https://archlinux.org/packages/extra/x86_64/lightdm/files/)
- [Official Xfce session files](https://archlinux.org/packages/extra/x86_64/xfce4-session/files/)
- [Xorg keyboard configuration](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration)
- [NetworkManager](https://wiki.archlinux.org/title/NetworkManager)
- [Locale](https://wiki.archlinux.org/title/Locale)
- [Sudo](https://wiki.archlinux.org/title/Sudo)
- [Official Firefox package](https://archlinux.org/packages/extra/x86_64/firefox/)
- [Official Thunar files](https://archlinux.org/packages/extra/x86_64/thunar/files/)

Arch Linux, Xfce, LightDM, Thunar, Firefox and their dependencies remain the
work of their respective upstream authors and Arch maintainers. Their licenses
are not replaced by NekoOS branding. The new overlay configuration and SVG are
original NekoOS project files; they do not use the Arch logo or reproduce an
upstream wallpaper.
