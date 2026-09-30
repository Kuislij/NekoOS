#!/usr/bin/env bash
set -euo pipefail

# Set the shipped wallpaper once; later user customisation is left intact.
state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nekoos"
[[ -e "$state_dir/desktop-initialized" ]] && exit 0
wallpaper=/usr/share/backgrounds/nekoos/neko.svg
channel=xfce4-desktop
mapfile -t properties < <(xfconf-query -c "$channel" -l | while IFS= read -r property; do
    case "$property" in
        /backdrop/*/last-image) printf '%s\n' "$property" ;;
    esac
done)
# A fresh xfconf channel may not have any stored backdrop properties yet.
# Use the actual connected XRandR outputs rather than a fixed QEMU name.
if [[ ${#properties[@]} -eq 0 ]]; then
    while read -r connector state _; do
        [[ "$state" == connected ]] || continue
        for workspace in 0 1 2 3; do
            properties+=("/backdrop/screen0/monitor$connector/workspace$workspace/last-image")
        done
    done < <(xrandr --query)
fi
[[ ${#properties[@]} -gt 0 ]] || exit 0
for property in "${properties[@]}"; do
    if xfconf-query -c "$channel" -p "$property" >/dev/null 2>&1; then
        xfconf-query -c "$channel" -p "$property" -s "$wallpaper"
    else
        xfconf-query -c "$channel" -p "$property" --create --type string --set "$wallpaper"
    fi
done
mkdir -p "$state_dir"
touch "$state_dir/desktop-initialized"
