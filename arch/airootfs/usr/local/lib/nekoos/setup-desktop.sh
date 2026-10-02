#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != --development || $# != 1 ]]; then
    printf 'Usage: setup-desktop.sh --development (inside the new Arch image)\n' >&2
    exit 2
fi
if [[ $(id -u) != 0 || ! -f /etc/arch-release || ! -f /usr/share/xsessions/xfce.desktop || ! -f /usr/share/nekoos/os-release ]]; then
    printf 'NekoOS setup requires the prepared Arch desktop image as root.\n' >&2
    exit 1
fi

locale-gen
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime

# A regular account is used for both the desktop and the serial QA console.
# This intentionally documented password belongs only to the local dev image.
getent group autologin >/dev/null || groupadd --system autologin
if ! id neko >/dev/null 2>&1; then
    useradd --create-home --uid 1000 --user-group --groups wheel,autologin --shell /bin/bash --comment 'NekoOS' neko
else
    usermod --append --groups wheel,autologin --shell /bin/bash neko
fi
printf 'neko:neko\n' | chpasswd
passwd --lock root
chown root:root /etc/sudoers.d /etc/sudoers.d/10-nekoos-wheel
chmod 0755 /etc/sudoers.d
chmod 0440 /etc/sudoers.d/10-nekoos-wheel
visudo --check --file /etc/sudoers

neko_home=$(getent passwd neko | cut -d: -f6)
for directory in Desktop Documents Downloads Templates Public Music Pictures Videos; do
    install -d -m 0755 -o neko -g neko "$neko_home/$directory"
done
for directory in .config .config/xfce4 .config/xfce4/xfconf .config/xfce4/xfconf/xfce-perchannel-xml; do
    install -d -m 0755 -o neko -g neko "$neko_home/$directory"
done
panel_config="$neko_home/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml"
if [[ ! -e "$panel_config" ]]; then
    install -m 0644 -o neko -g neko /etc/xdg/xfce4/panel/default.xml "$panel_config"
fi
chmod 0755 /usr/local/lib/nekoos/setup-desktop.sh /usr/local/lib/nekoos/desktop-first-login.sh
chmod 0755 /usr/local/bin/neko-update

# Upstream grub-mkconfig reads /etc/default/grub, not grub.d drop-ins.
# Source our small override explicitly, keeping the packaged defaults.
grub_override='. /etc/default/grub.d/50-nekoos.cfg'
if ! grep -qFx "$grub_override" /etc/default/grub; then
    printf '\n%s\n' "$grub_override" >> /etc/default/grub
fi

# /etc/os-release is a distribution override. Keep Arch's package-owned
# /usr/lib/os-release untouched, including when /etc began as its symlink.
install -m 0644 /usr/share/nekoos/os-release /etc/os-release.neko-new
mv -fT /etc/os-release.neko-new /etc/os-release

systemctl enable NetworkManager.service lightdm.service serial-getty@ttyS0.service
systemctl set-default graphical.target
printf 'NEKO_ARCH_DESKTOP_CONFIGURED\n'
