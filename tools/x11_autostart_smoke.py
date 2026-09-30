#!/usr/bin/env python3
"""Boot a disposable QEMU guest with the opt-in X11 session auto-started."""

import subprocess
import sys
import tempfile
from pathlib import Path

from boot_test import ROOT, run_disk_guest


GUEST_COMMAND = b'''attempt=0
a11y_processes_alive() {
    for proc_comm in /proc/[0-9]*/comm; do
        process_name=$(cat "$proc_comm" 2>/dev/null || true)
        case "$process_name" in
            at-spi-bus-laun*|at-spi2-registr*) return 0 ;;
        esac
    done
    return 1
}
while ! grep -Fq NEKO_X11_SESSION_RUNNING /run/neko/services/desktop.log 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then break; fi
    sleep 1
done
if grep -Fq NEKO_X11_SESSION_RUNNING /run/neko/services/desktop.log &&
   grep -Fq NEKO_X11_SESSION_BUS_RUNNING /run/neko/services/desktop.log &&
   neko-service status desktop &&
   test -S /tmp/.X11-unix/X1 &&
   bus_address=$(cat /run/neko-x11-session.*/dbus.address) &&
   DBUS_SESSION_BUS_ADDRESS="$bus_address" setuidgid neko gdbus call --session \
       --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
       --method org.freedesktop.DBus.ListNames | grep -Fq org.freedesktop.DBus &&
   a11y_address=$(DBUS_SESSION_BUS_ADDRESS="$bus_address" setuidgid neko gdbus call --session \
       --dest org.a11y.Bus --object-path /org/a11y/bus \
       --method org.a11y.Bus.GetAddress) &&
   a11y_address=${a11y_address#*"'"} &&
   a11y_address=${a11y_address%%"'"*} &&
   test -n "$a11y_address" &&
   setuidgid neko gdbus introspect --address "$a11y_address" \
       --dest org.a11y.atspi.Registry --object-path /org/a11y/atspi/registry \
       > /tmp/neko-registry-introspection &&
   grep -Fq org.a11y.atspi.Registry /tmp/neko-registry-introspection &&
   DISPLAY=:1 neko-x11-extensions-check &&
   DISPLAY=:1 neko-evilwm-check &&
   neko-service stop desktop; then
    attempt=0
    while { test -S /tmp/.X11-unix/X1 || a11y_processes_alive; } && [ "$attempt" -lt 10 ]; do
        sleep 1
        attempt=$((attempt + 1))
    done
    if ! test -S /tmp/.X11-unix/X1 && ! a11y_processes_alive; then
        printf '\n%s%s\n' 'NEKO_X11_AUTOSTART_' 'READY'
    else
        echo NEKO_X11_A11Y_CLEANUP_FAILED
        ps
    fi
fi
poweroff
'''


def main():
    images = ROOT / 'out/images'
    if not (images / 'initramfs.cpio.gz').is_file():
        raise RuntimeError('build the NekoOS image first')
    with tempfile.TemporaryDirectory(prefix='x11-autostart-',
                                     dir=ROOT / 'build') as directory:
        for pass_number in (1, 2):
            state_disk = Path(directory) / f'state-{pass_number}.img'
            subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state_disk),
                            '128M'], check=True, stdout=subprocess.DEVNULL)
            subprocess.run(['mkfs.ext4', '-F', '-q', str(state_disk)],
                           check=True, stdout=subprocess.DEVNULL)
            system_disk = None
            if pass_number == 2:
                system_disk = Path(directory) / 'system.img'
                subprocess.run(['cp', '--sparse=always',
                                str(images / 'system-template.img'),
                                str(system_disk)], check=True)
            run_disk_guest(images, state_disk, GUEST_COMMAND,
                           'NEKO_X11_AUTOSTART_READY', pass_number, 120,
                           False, log_prefix='x11-autostart', video=True,
                           system_disk=system_disk,
                           kernel_extra='neko.x11=1')
    print('X11_AUTOSTART_SMOKE_PASSED: automatic Xorg session and clean service stop from initramfs and system disk')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'X11_AUTOSTART_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
