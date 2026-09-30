#!/usr/bin/env python3
"""Verify real GTK widgets and persistent UTF-8 notes in disposable QEMU guests."""

import hashlib
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

from boot_test import ROOT, run_disk_guest


# This is the UTF-8 note written by neko-gtk-welcome's explicit self-test mode.
EXPECTED_NOTE = 'Проверка NekoOS: заметка в UTF-8.\nВторая строка: кот и окна.\n'
NOTE_SHA256 = hashlib.sha256(EXPECTED_NOTE.encode('utf-8')).hexdigest()
INITRAMFS_NOTE = '/home/neko/Documents/gtk-initramfs-note.txt'
SYSTEM_NOTE = '/home/neko/Documents/gtk-smoke-note.txt'
RERUN_NOTE = '/home/neko/Documents/gtk-rerun-note.txt'


def guest_command(note_path, persisted_notes=(), exercise_session=False, marker='GTK_SMOKE_READY'):
    """Check existing notes before invoking anything that can write test notes."""
    validate = '''gtk_validate_note() {
    test -f "$1" &&
    /usr/bin/setuidgid neko /bin/sh -c '[ -O "$1" ]' sh "$1" &&
    checksum=$(sha256sum "$1") &&
    test "${checksum%% *}" = ''' + shlex.quote(NOTE_SHA256) + '''
}
gtk_wait_display() {
    attempt=0
    while ! grep -Fq NEKO_X11_SESSION_RUNNING /run/neko/services/desktop.log 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 30 ]; then return 1; fi
        sleep 1
    done
    grep -Fq NEKO_X11_SESSION_BUS_RUNNING /run/neko/services/desktop.log &&
    neko-service status desktop && test -S /tmp/.X11-unix/X1
}
'''
    conditions = [f'gtk_validate_note {shlex.quote(path)}' for path in persisted_notes]
    if exercise_session:
        validate += '''gtk_check_session() {
    neko-service stop desktop || return 1
    attempt=0
    while test -S /tmp/.X11-unix/X1; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 15 ]; then return 1; fi
        sleep 1
    done
    neko-x11-session --self-test && neko-service start desktop
}
'''
        conditions.append('gtk_check_session')
    conditions += [
        'gtk_wait_display',
        'bus_address=$(head -n 1 /run/neko-x11-session.*/dbus.address)',
        'test "${bus_address#unix:}" != "$bus_address"',
        'HOME=/home/neko USER=neko LOGNAME=neko DISPLAY=:1 GDK_BACKEND=x11 '
        'GSETTINGS_BACKEND=memory DBUS_SESSION_BUS_ADDRESS="$bus_address" '
        '/usr/bin/setuidgid neko /usr/bin/neko-gtk-welcome --self-test '
        + shlex.quote(note_path),
        f'gtk_validate_note {shlex.quote(note_path)}',
        'sync',
        'neko-service stop desktop',
    ]
    # Splitting the marker prevents the serial console's command echo from
    # satisfying run_disk_guest's requirement for an actual output line.
    midpoint = marker.rfind('_') + 1
    command = validate + 'if ' + ' &&\n   '.join(conditions) + '; then\n'
    command += "    printf '\\n%s%s\\n' " + shlex.quote(marker[:midpoint])
    command += ' ' + shlex.quote(marker[midpoint:]) + '\n'
    command += '''else
    printf '\\nGTK_SMOKE_GUEST_FAILED\\n'
    cat /run/neko/services/desktop.log 2>/dev/null || true
    cat /run/neko-x11-session.*/welcome.log 2>/dev/null || true
fi
poweroff
'''
    return command.encode('utf-8')


def main():
    images = ROOT / 'out/images'
    for name in ('bzImage', 'initramfs.cpio.gz', 'bootstrap.cpio.gz', 'system-template.img'):
        if not (images / name).is_file():
            raise RuntimeError(f'build the NekoOS GTK image first: missing {name}')
    with tempfile.TemporaryDirectory(prefix='gtk-smoke-', dir=ROOT / 'build') as directory:
        state_disk = Path(directory) / 'state.img'
        system_disk = Path(directory) / 'system.img'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state_disk), '128M'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(state_disk)],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['cp', '--sparse=always', str(images / 'system-template.img'),
                        str(system_disk)], check=True)
        passes = (
            (INITRAMFS_NOTE, (), True, None, 'GTK_INITRAMFS_READY'),
            (SYSTEM_NOTE, (INITRAMFS_NOTE,), False, system_disk, 'GTK_SYSTEM_WRITE_READY'),
            (RERUN_NOTE, (INITRAMFS_NOTE, SYSTEM_NOTE), False, system_disk,
             'GTK_NOTES_PERSISTENCE_READY'),
        )
        for pass_number, (note_path, existing, session_test, root_disk, marker) in enumerate(passes, 1):
            run_disk_guest(images, state_disk,
                           guest_command(note_path, existing, session_test, marker),
                           marker, pass_number, 150, False, log_prefix='gtk-smoke',
                           video=True, system_disk=root_disk, kernel_extra='neko.x11=1')
    print('GTK_SMOKE_PASSED: real GTK widgets, fonts and PNG, visible Save errors, '
          'UTF-8 notes preserved across initramfs and two system-disk boots')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'GTK_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
