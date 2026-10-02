#!/usr/bin/env bash
# NekoOS profile; boot and mkinitcpio templates come from signed archiso 90-1.
iso_name="nekoos-live"
iso_label="NEKO_20261001"
iso_publisher="NekoOS <https://github.com/Kuislij/NekoOS>"
iso_application="NekoOS Live Desktop"
iso_version="2026.10.01"
install_dir="neko"
arch="x86_64"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '9' '-b' '1M' '-processors' '2')
file_permissions=(
  ["/usr/local/bin/neko-update"]="0:0:755"
  ["/etc/sudoers.d/10-nekoos-wheel"]="0:0:440"
  ["/usr/local/lib/nekoos/setup-desktop.sh"]="0:0:755"
  ["/usr/local/lib/nekoos/desktop-first-login.sh"]="0:0:755"
)
