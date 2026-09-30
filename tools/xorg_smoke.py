#!/usr/bin/env python3
"""Boot a disposable QEMU guest and prove Xorg delivers real input to Xlib."""

import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from boot_test import (ROOT, graphics_monitor_option, graphics_monitor_path,
                       graphics_qmp_path, graphics_absolute_input, hmp_response)


GUEST_COMMAND = b'''neko-service stop desktop || true
keyboard=
pointer=
for event in /dev/input/event*; do
    if test -c "$event"; then
        name=$(cat "/sys/class/input/${event##*/}/device/name" 2>/dev/null || true)
        printf 'XORG_INPUT_FOUND: %s %s\n' "$event" "$name"
        case "$name" in
            *Keyboard*) keyboard=$event ;;
            *Mouse*|*Tablet*) pointer=$event ;;
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
    # QEMU's tablet must deliver absolute positions, not touchpad deltas.
    Option "Mode" "Absolute"
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
if test "$ready" = 1 && DISPLAY=:1 neko-xorg-window-check --input &&
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


def send_input(monitor_path, qmp_path, deadline):
    """Inject input through QEMU, rather than synthesizing X11 client events."""
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        while time.monotonic() < deadline:
            try:
                connection.settimeout(min(2.0, deadline - time.monotonic()))
                connection.connect(str(monitor_path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.05)
        else:
            raise RuntimeError('QEMU monitor did not become available')
        hmp_response(connection, deadline)
        connection.sendall(b'sendkey a\n')
        hmp_response(connection, deadline)
        graphics_absolute_input(qmp_path, deadline)
        for command in ('mouse_button 1', 'mouse_button 0'):
            connection.sendall((command + '\n').encode('ascii'))
            hmp_response(connection, deadline)
            time.sleep(0.15)
    finally:
        connection.close()


def run_xorg_guest(images, disk):
    log = ROOT / 'build/logs/xorg-smoke-test-1.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    monitor_path = graphics_monitor_path()
    qmp_path = graphics_qmp_path()
    command = [
        'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg',
        '-cpu', 'qemu64', '-m', '512M', '-smp', '2', '-nodefaults',
        '-display', 'none', '-monitor', graphics_monitor_option(monitor_path),
        '-qmp', graphics_monitor_option(qmp_path),
        '-serial', 'stdio', '-nic', 'none', '-no-reboot',
        '-device', 'virtio-vga', '-device', 'virtio-keyboard-pci',
        '-device', 'virtio-tablet-pci',
        '-drive', f'file={disk},format=raw,if=virtio',
        '-kernel', str(images / 'bzImage'),
        '-initrd', str(images / 'initramfs.cpio.gz'),
        '-append', 'console=ttyS0,115200 rdinit=/init panic=-1 '
                   'neko.state=required',
    ]
    with log.open('wb') as output:
        process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 120
            command_sent = False
            input_sent = False
            while time.monotonic() < deadline:
                content = log.read_text(errors='replace')
                lines = content.replace('\r', '').splitlines()
                ready = ('SYSTEM_READY' in lines and
                         'PERSISTENCE_READY' in lines and
                         'built-in shell (ash)' in content)
                if ready and not command_sent:
                    process.stdin.write(GUEST_COMMAND)
                    process.stdin.flush()
                    command_sent = True
                if 'XORG_INPUT_CLIENT_READY' in lines and not input_sent:
                    send_input(monitor_path, qmp_path, deadline)
                    input_sent = True
                code = process.poll()
                if code is not None:
                    lines = log.read_text(errors='replace').replace('\r', '').splitlines()
                    markers = ('XORG_CLIENT_READY', 'XORG_INPUT_CLIENT_READY',
                               'XORG_KEY_EVENT_READY', 'XORG_MOUSE_EVENT_READY',
                               'XORG_POINTER_MOVE_READY',
                               'XORG_CLIENT_INPUT_READY', 'XORG_INPUT_READY',
                               'XORG_DISPLAY_READY')
                    if (code == 0 and command_sent and input_sent and
                            all(any(line.endswith(marker) for line in lines)
                                for marker in markers) and
                            any('Power down' in line for line in lines)):
                        return
                    raise RuntimeError(f'Xorg input smoke failed; see {log}')
                if 'Kernel panic' in content or 'BOOT_FAILED:' in content:
                    raise RuntimeError(f'Xorg guest boot failed; see {log}')
                time.sleep(0.1)
            raise RuntimeError(f'Xorg input smoke timed out; see {log}')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            process.stdin.close()
            monitor_path.unlink(missing_ok=True)
            qmp_path.unlink(missing_ok=True)


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
        run_xorg_guest(images, state_disk)
    print('XORG_SMOKE_PASSED: Xorg delivered QEMU keyboard and mouse input to an independent Xlib window')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'XORG_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
