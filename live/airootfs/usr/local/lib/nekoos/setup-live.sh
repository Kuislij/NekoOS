#!/usr/bin/env bash
set -euo pipefail
bash /usr/local/lib/nekoos/setup-desktop.sh --development
install -d -m 0755 /usr/share/nekoos
printf 'ephemeral-live\n' > /usr/share/nekoos/live-mode
# Archiso removes build caches. Prepare fonts before SVG decoding starts;
# do not relax glycin's image-decoder sandbox to permit cache writes.
systemctl enable neko-live-font-cache.service
# No network login or first-boot installation services are enabled.
systemctl mask sshd.service sshd.socket systemd-gpt-auto-generator.service
install -d -m 0755 /etc/systemd/system-generators
ln -sf /dev/null /etc/systemd/system-generators/systemd-gpt-auto-generator
ln -sf /dev/null /etc/systemd/system-generators/systemd-gpt-auto-generator.efi
printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' > /etc/pacman.d/mirrorlist
cat >> /home/neko/README-NekoOS.txt <<'EOF'

Это Live-сеанс с флешки или ISO. Файлы этого сеанса находятся в памяти
и исчезнут после выключения. Установщик пока не включён.
Внутренние диски не подключаются автоматически.
Пользователь и пароль демонстрационного сеанса: neko.
EOF
chown neko:neko /home/neko/README-NekoOS.txt
# This image-only hook must not run again when a live user installs a package.
rm -f /etc/pacman.d/hooks/95-neko-live.hook
printf 'NEKO_LIVE_CONFIGURED\n'
