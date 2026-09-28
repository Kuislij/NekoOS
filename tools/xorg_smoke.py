#!/usr/bin/env python3
"""Boot a disposable QEMU guest and prove Xorg accepts a separate Xlib client."""

import subprocess
import sys
import tempfile
from pathlib import Path

from boot_test import ROOT, run_disk_guest


GUEST_COMMAND = b'''neko-service stop desktop || true
keyboard=
pointer=
for event in /dev/input/event*; do
    if test -c "$event"; then
        name=$(cat "/sys/class/input/${event##*/}/device/name" 2>/dev/null || true)
        printf 'XORG_INPUT_FOUND: %s %s\n' "$event" "$name"
        case "$name" in
            *Keyboard*) keyboard=$event ;;
            *Mouse*) pointer=$event ;;
        esac
    fi
done
if test -z "$keyboard" || test -z "$pointer"; then
    printf '\nXORG_INPUT_FAILED\n'
    poweroff
fi
cat > /tmp/neko-xorg.conf <<EOF
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AllowEmptyInput" "true"
EndSection
Section "Device"
    Identifier "Video0"
    Driver "modesetting"
    Option "kmsdev" "/dev/dri/card0"
    Option "AccelMethod" "none"
    Option "ShadowFB" "true"
    Option "SWcursor" "true"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "Video0"
EndSection
Section "InputDevice"
    Identifier "Keyboard0"
    Driver "evdev"
    Option "Device" "$keyboard"
    Option "CoreKeyboard"
EndSection
Section "InputDevice"
    Identifier "Mouse0"
    Driver "evdev"
    Option "Device" "$pointer"
    Option "CorePointer"
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen "Screen0"
    InputDevice "Keyboard0" "CoreKeyboard"
    InputDevice "Mouse0" "CorePointer"
EndSection
EOF
Xorg :1 vt2 -config /tmp/neko-xorg.conf -logfile /tmp/neko-xorg.log -nolisten tcp -noreset > /tmp/neko-xorg.stdout 2>&1 &
xorg_pid=$!
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if test -S /tmp/.X11-unix/X1; then ready=1; break; fi
    sleep 1
done
if test "$ready" = 1 && DISPLAY=:1 neko-xorg-window-check &&
   grep -Fq "Using input driver 'evdev' for 'Keyboard0'" /tmp/neko-xorg.log &&
   grep -Fq "Using input driver 'evdev' for 'Mouse0'" /tmp/neko-xorg.log; then
    printf '\nXORG_INPUT_READY\n'
    printf '\nXORG_DISPLAY_READY\n'
else
    tail -80 /tmp/neko-xorg.log 2>/dev/null || true
    tail -40 /tmp/neko-xorg.stdout 2>/dev/null || true
    printf '\nXORG_DISPLAY_FAILED\n'
fi
kill "$xorg_pid" 2>/dev/null || true
wait "$xorg_pid" 2>/dev/null || true
poweroff
'''


def main():
    images = ROOT / 'out/images'
    if not (images / 'initramfs.cpio.gz').is_file():
        raise RuntimeError('build the NekoOS image first')
    with tempfile.TemporaryDirectory(prefix='xorg-smoke-', dir=ROOT / 'build') as directory:
        state_disk = Path(directory) / 'state.img'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state_disk), '128M'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(state_disk)],
                       check=True, stdout=subprocess.DEVNULL)
        run_disk_guest(images, state_disk, GUEST_COMMAND, 'XORG_DISPLAY_READY',
                       1, 120, False, log_prefix='xorg-smoke', video=True)
    print('XORG_SMOKE_PASSED: Xorg loaded evdev input and displayed an independent Xlib window in QEMU')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'XORG_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
