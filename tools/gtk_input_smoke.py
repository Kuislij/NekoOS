#!/usr/bin/env python3
"""Use QEMU keyboard/tablet events to save and close the real GTK note window."""

import hashlib
import json
import socket
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from boot_test import ROOT


NOTE = '/home/neko/Documents/Neko-note.txt'
TEXT = 'neko input works'


def wait_log(process, log, marker, deadline):
    while time.monotonic() < deadline:
        content = log.read_text(errors='replace').replace('\r', '')
        if marker in content.splitlines():
            return
        if 'GTK_INPUT_GUEST_FAILED' in content.splitlines():
            raise RuntimeError(f'guest assertion failed; see {log}')
        if process.poll() is not None or 'Kernel panic' in content:
            raise RuntimeError(f'guest exited before {marker}; see {log}')
        time.sleep(0.1)
    raise RuntimeError(f'timed out waiting for {marker}; see {log}')


def send_guest(process, command):
    process.stdin.write(command.encode('utf-8') + b'\n')
    process.stdin.flush()


def output_marker(marker):
    midpoint = marker.rfind('_') + 1
    return f"printf '\\n%s%s\\n' '{marker[:midpoint]}' '{marker[midpoint:]}'"


def assert_note(process, log, text, marker, deadline):
    digest = hashlib.sha256(text.encode('utf-8')).hexdigest()
    command = f'''attempt=0
while :; do
    if test -f {NOTE} && checksum=$(sha256sum {NOTE}) &&
       test "${{checksum%% *}}" = {digest}; then break; fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 10 ]; then break; fi
    sleep 1
done
if test "$attempt" -lt 10 &&
   setuidgid neko /bin/sh -c '[ -O "$1" ]' sh {NOTE}; then
    {output_marker(marker)}
else
    printf '\\nGTK_INPUT_GUEST_FAILED\\n'
fi'''
    send_guest(process, command)
    wait_log(process, log, marker, deadline)


def main():
    images = ROOT / 'out/images'
    for name in ('bzImage', 'bootstrap.cpio.gz', 'system-template.img'):
        if not (images / name).is_file():
            raise RuntimeError(f'build the NekoOS GTK image first: missing {name}')
    previews = ROOT / 'out/previews'
    previews.mkdir(parents=True, exist_ok=True)
    log = ROOT / 'build/logs/gtk-input-smoke.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='gtk-input-', dir=ROOT / 'build') as directory:
        work = Path(directory)
        state = work / 'state.img'
        system = work / 'system.img'
        qmp_path = work / 'qmp.sock'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state), '128M'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(state)],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['cp', '--sparse=always', str(images / 'system-template.img'),
                        str(system)], check=True)
        command = [
            'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'qemu64',
            '-m', '512M', '-smp', '2', '-nodefaults', '-display', 'none',
            '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot',
            '-qmp', f'unix:{qmp_path},server=on,wait=off',
            '-device', 'virtio-vga', '-device', 'virtio-keyboard-pci',
            '-device', 'virtio-tablet-pci',
            '-drive', f'file={system},format=raw,if=virtio',
            '-drive', f'file={state},format=raw,if=virtio',
            '-kernel', str(images / 'bzImage'), '-initrd', str(images / 'bootstrap.cpio.gz'),
            '-append', 'console=ttyS0,115200 rdinit=/init panic=-1 '
                       'neko.system=required neko.state=required neko.x11=1',
        ]
        connection = None
        stream = None
        execute = None
        with log.open('wb') as output:
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output,
                                       stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 150
                wait_log(process, log, 'SYSTEM_READY', deadline)
                send_guest(process, '''attempt=0
while ! grep -Fq GTK_WINDOW_MAPPED /run/neko-x11-session.*/welcome.log 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then break; fi
    sleep 1
done
if [ "$attempt" -lt 30 ]; then
    ''' + output_marker('GTK_INPUT_WINDOW_READY') + '''
else
    printf '\\nGTK_INPUT_GUEST_FAILED\\n'
fi''')
                wait_log(process, log, 'GTK_INPUT_WINDOW_READY', deadline)
                connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                connection.settimeout(10)
                connection.connect(str(qmp_path))
                stream = connection.makefile('rwb')
                json.loads(stream.readline())

                def qmp(name, arguments=None):
                    request = {'execute': name}
                    if arguments is not None:
                        request['arguments'] = arguments
                    stream.write(json.dumps(request).encode() + b'\n')
                    stream.flush()
                    while True:
                        reply = json.loads(stream.readline())
                        if 'error' in reply:
                            raise RuntimeError(f'QMP failed: {reply["error"]}')
                        if 'return' in reply:
                            return reply['return']

                execute = qmp
                qmp('qmp_capabilities')
                mice = qmp('query-mice')
                if not any(mouse['current'] and mouse['absolute'] for mouse in mice):
                    raise RuntimeError('QEMU has no active absolute pointer')

                def screenshot(name):
                    path = previews / name
                    qmp('screendump', {'filename': str(path), 'format': 'png'})
                    return path

                screen = screenshot('gtk-input-start.png')
                width, height = struct.unpack('>II', screen.read_bytes()[16:24])
                if (width, height) != (1280, 800):
                    raise RuntimeError(f'GTK input layout expects 1280x800, got {width}x{height}')

                def key(name):
                    qmp('human-monitor-command', {'command-line': 'sendkey ' + name})
                    time.sleep(0.15)

                def click(x, y):
                    qmp('input-send-event', {'events': [
                        {'type': 'abs', 'data': {'axis': 'x', 'value': x * 32767 // (width - 1)}},
                        {'type': 'abs', 'data': {'axis': 'y', 'value': y * 32767 // (height - 1)}},
                    ]})
                    time.sleep(0.1)
                    for down in (True, False):
                        qmp('input-send-event', {'events': [
                            {'type': 'btn', 'data': {'button': 'left', 'down': down}},
                        ]})
                        time.sleep(0.15)

                # These are the centers of real controls in the fixed guest
                # resolution. No application self-test or synthetic touch is used.
                key('ctrl-a')
                for character in TEXT:
                    key('spc' if character == ' ' else character)
                click(799, 630)
                assert_note(process, log, TEXT, 'GTK_INPUT_SAVE_READY', deadline)
                screenshot('gtk-input-saved.png')

                click(500, 430)
                key('ctrl-end')
                key('x')
                click(910, 630)
                time.sleep(0.5)
                assert_note(process, log, TEXT, 'GTK_INPUT_UNSAVED_NOTE_READY', deadline)
                send_guest(process, 'if test -S /tmp/.X11-unix/X1; then ' +
                           output_marker('GTK_INPUT_DIALOG_OPEN') +
                           "; else printf '\\nGTK_INPUT_GUEST_FAILED\\n'; fi")
                wait_log(process, log, 'GTK_INPUT_DIALOG_OPEN', deadline)
                screenshot('gtk-unsaved-dialog.png')
                # This editor point lies behind and outside the modal dialog.
                # If Close missed its button, the editor accepts "y" and the
                # exact hash after Cancel/Save below must fail. A real modal
                # dialog blocks this attempt to change the parent buffer.
                click(340, 500)
                key('y')
                key('esc')
                click(799, 630)
                assert_note(process, log, TEXT + 'x', 'GTK_INPUT_CANCEL_SAVE_READY', deadline)
                screenshot('gtk-input-saved.png')
                click(910, 630)
                send_guest(process, '''attempt=0
while test -S /tmp/.X11-unix/X1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 15 ]; then break; fi
    sleep 1
done
if [ "$attempt" -lt 15 ] && neko-service status desktop; then
    ''' + output_marker('GTK_INPUT_CLOSE_READY') + '''
else
    printf '\\nGTK_INPUT_GUEST_FAILED\\n'
fi''')
                wait_log(process, log, 'GTK_INPUT_CLOSE_READY', deadline)
                send_guest(process, 'poweroff')
                process.wait(timeout=15)
                if process.returncode != 0 or 'Power down' not in log.read_text(errors='replace'):
                    raise RuntimeError(f'guest did not shut down cleanly; see {log}')
            except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
                if execute is not None and process.poll() is None:
                    try:
                        execute('screendump', {'filename': str(previews / 'gtk-input-failed.png'),
                                              'format': 'png'})
                    except (OSError, RuntimeError, ValueError):
                        pass
                raise
            finally:
                if process.poll() is None:
                    try:
                        send_guest(process, 'poweroff')
                        process.wait(timeout=15)
                    except (OSError, subprocess.TimeoutExpired):
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                process.stdin.close()
                if stream is not None:
                    stream.close()
                if connection is not None:
                    connection.close()
    print('GTK_INPUT_SMOKE_PASSED: real keyboard/tablet Save, unsaved Close/Cancel, '
          'second Save and clean Close in disposable QEMU')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f'GTK_INPUT_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
