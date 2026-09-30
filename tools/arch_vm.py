#!/usr/bin/env python3
"""Run the Arch desktop or test it twice on a disposable persistent disk."""

import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time

if sys.platform == 'linux':
    import fcntl


ROOT = Path(__file__).resolve().parents[1]
IMAGE_NAMES = ('vmlinuz-linux', 'initramfs-linux.img', 'system-template.img',
               'packages.lock', 'snapshot.txt', 'boot-mode.txt')
FOLDER = '/home/neko/neko-gui-check'
NOTE = 'NekoOS: сохранённый файл после перезагрузки.\n'


def safe_directory(path, create=False):
    """Reject symlink ancestors before operating inside a managed directory."""
    path = Path(path).absolute()
    for component in reversed((path, *path.parents)):
        try:
            mode = component.lstat().st_mode
        except FileNotFoundError:
            if not create:
                raise RuntimeError(f'Missing directory: {component}') from None
            component.mkdir()
            mode = component.lstat().st_mode
        if not stat.S_ISDIR(mode):
            raise RuntimeError(f'Unsafe directory: {component}')
    return path


def safe_regular(path, writable=False):
    path = Path(path)
    safe_directory(path.parent)
    try:
        info = path.lstat()
    except FileNotFoundError:
        raise RuntimeError(f'Missing file: {path}') from None
    if not stat.S_ISREG(info.st_mode) or (writable and info.st_nlink != 1):
        raise RuntimeError(f'Unsafe file: {path}')
    return info


def read_regular(path):
    safe_regular(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise RuntimeError(f'Unsafe file: {path}')
        return stream.read()


def sha256_file(path):
    safe_regular(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    digest = hashlib.sha256()
    with os.fdopen(descriptor, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise RuntimeError(f'Unsafe file: {path}')
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


@contextmanager
def file_lock(path, shared=False):
    safe_directory(path.parent, create=True)
    descriptor = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'a+b') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise RuntimeError(f'Unsafe lock: {path}')
        try:
            operation = fcntl.LOCK_SH if shared else fcntl.LOCK_EX
            fcntl.flock(stream, operation | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError(f'Another build or VM is using {path.name}') from None
        yield


def verify_images(root=ROOT):
    images = safe_directory(root / 'out/arch/images')
    text = read_regular(images / 'SHA256SUMS').decode('ascii')
    if not text.endswith('\n'):
        raise RuntimeError('Image manifest must end with a newline')
    hashes = {}
    for line in text[:-1].split('\n'):
        match = re.fullmatch(r'([0-9a-f]{64})  ([a-z][a-z0-9.-]*)', line)
        if match is None or match[2] not in IMAGE_NAMES:
            raise RuntimeError('Image manifest has a malformed or unsafe entry')
        if match[2] in hashes:
            raise RuntimeError(f'Image manifest repeats {match[2]}')
        hashes[match[2]] = match[1]
    if set(hashes) != set(IMAGE_NAMES):
        missing = ', '.join(sorted(set(IMAGE_NAMES) - set(hashes)))
        raise RuntimeError(f'Image manifest is incomplete: {missing}')
    for name in IMAGE_NAMES:
        if sha256_file(images / name) != hashes[name]:
            raise RuntimeError(f'Image checksum verification failed: {name}')
    mode = read_regular(images / 'boot-mode.txt')
    if mode not in (b'grub\n', b'direct\n'):
        raise RuntimeError('Unsupported Arch image boot mode')
    return images, hashes, mode.decode().strip()


def ensure_images(root, no_build):
    safe_directory(root / 'out/arch', create=True)
    images = root / 'out/arch/images'
    if os.path.lexists(images):
        safe_directory(images)
        return
    if no_build:
        raise RuntimeError('Arch images are missing; run bash os arch build first')
    subprocess.run(['bash', str(root / 'scripts/arch-build.sh')], check=True)


def snapshot_file(source, destination, digest):
    """Hardlinks remain attached to the old inode after an atomic image rebuild."""
    if os.path.lexists(destination):
        safe_regular(destination)
        source_info, destination_info = source.stat(), destination.stat()
        same_inode = ((source_info.st_dev, source_info.st_ino) ==
                      (destination_info.st_dev, destination_info.st_ino))
        if not same_inode and sha256_file(destination) != digest:
            raise RuntimeError(f'Immutable VM base checksum failed: {destination.name}')
    else:
        os.link(source, destination, follow_symlinks=False)
    destination.chmod(0o444)


def qcow_info(path):
    safe_regular(path, writable=True)
    result = subprocess.run(['qemu-img', 'info', '-f', 'qcow2', '--output=json', str(path)],
                            check=True, stdout=subprocess.PIPE, text=True)
    return json.loads(result.stdout)


def validate_qcow(path, base):
    info = qcow_info(path)
    if (info.get('format') != 'qcow2' or
            info.get('backing-filename') != str(base) or
            info.get('full-backing-filename') != str(base) or
            info.get('backing-filename-format') != 'raw'):
        raise RuntimeError('Persistent VM disk has an unexpected backing file; preserving it')
    data = info.get('format-specific', {}).get('data', {})
    if info.get('data-file') or data.get('data-file') or data.get('corrupt'):
        raise RuntimeError('Persistent VM disk has unsafe external data or corrupt metadata')


def create_qcow(path, base):
    if os.path.lexists(path):
        raise RuntimeError(f'Refusing to replace an existing VM disk: {path}')
    descriptor, temporary_name = tempfile.mkstemp(prefix='.system-new-', dir=path.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        subprocess.run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'raw',
                        '-b', str(base), str(temporary)], check=True,
                       stdout=subprocess.DEVNULL)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def prepare_persistent(root, verified):
    images, hashes, mode = verified
    directory = safe_directory(root / 'out/arch/disks', create=True)
    disk = directory / 'system.qcow2'
    metadata = directory / 'system.json'
    if os.path.lexists(disk) or os.path.lexists(metadata):
        safe_regular(disk, writable=True)
        record = json.loads(read_regular(metadata))
        if not isinstance(record, dict):
            raise RuntimeError('Invalid persistent VM metadata; preserving the disk')
        expected_keys = {'version', 'base', 'mode'}
        if record.get('mode') == 'direct':
            expected_keys |= {'kernel', 'initramfs'}
        if (set(record) != expected_keys or record.get('version') != 1 or
                record.get('mode') not in ('grub', 'direct') or
                any(not isinstance(record.get(key), str) or
                    re.fullmatch('[0-9a-f]{64}', record[key]) is None
                    for key in expected_keys - {'version', 'mode'})):
            raise RuntimeError('Invalid persistent VM metadata; preserving the disk')
        base = directory / f'base-{record["base"]}.img'
        if sha256_file(base) != record['base']:
            raise RuntimeError('Immutable VM base checksum failed; preserving the disk')
        validate_qcow(disk, base)
    else:
        record = {'version': 1, 'base': hashes['system-template.img'], 'mode': mode}
        base = directory / f'base-{record["base"]}.img'
        snapshot_file(images / 'system-template.img', base, record['base'])
        if mode == 'direct':
            record['kernel'] = hashes['vmlinuz-linux']
            record['initramfs'] = hashes['initramfs-linux.img']
            for name, key in (('vmlinuz-linux', 'kernel'), ('initramfs-linux.img', 'initramfs')):
                snapshot_file(images / name, directory / f'{key}-{record[key]}.img', record[key])
        create_qcow(disk, base)
        descriptor, temporary_name = tempfile.mkstemp(prefix='.metadata-new-', dir=directory)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, 'w') as stream:
                json.dump(record, stream, sort_keys=True)
                stream.write('\n')
            temporary.replace(metadata)
        finally:
            temporary.unlink(missing_ok=True)
    kernel = initramfs = None
    if record['mode'] == 'direct':
        kernel = directory / f'kernel-{record["kernel"]}.img'
        initramfs = directory / f'initramfs-{record["initramfs"]}.img'
        for path, key in ((kernel, 'kernel'), (initramfs, 'initramfs')):
            if sha256_file(path) != record[key]:
                raise RuntimeError(f'Immutable direct-boot {key} checksum failed')
    return disk, record['mode'], kernel, initramfs


def acceleration():
    if os.access('/dev/kvm', os.R_OK | os.W_OK):
        return ['-accel', 'kvm', '-cpu', 'host']
    return ['-accel', 'tcg', '-cpu', 'max']


def uefi_firmware(directory):
    """Use a read-only host CODE image and a private disposable VARS copy."""
    for suffix in ('_4M', ''):
        code = Path(f'/usr/share/OVMF/OVMF_CODE{suffix}.fd')
        variables = Path(f'/usr/share/OVMF/OVMF_VARS{suffix}.fd')
        if code.is_file() and variables.is_file():
            safe_regular(code)
            safe_regular(variables)
            private = directory / 'OVMF_VARS.fd'
            if os.path.lexists(private):
                raise RuntimeError('Refusing to replace private UEFI variables')
            shutil.copyfile(variables, private)
            private.chmod(0o600)
            return code, private
    raise RuntimeError('UEFI requires host OVMF_CODE[_4M].fd and OVMF_VARS[_4M].fd')


def qemu_command(disk, mode, kernel=None, initramfs=None, headless=False, qmp_path=None,
                 firmware=None, no_reboot=False):
    command = ['qemu-system-x86_64', '-machine', 'q35', *acceleration(),
               '-m', '2048M', '-smp', '2', '-nodefaults',
               '-display', 'none' if headless else 'gtk',
               '-monitor', 'none', '-serial', 'stdio',
               '-device', 'virtio-vga', '-device', 'qemu-xhci',
               '-device', 'usb-kbd', '-device', 'usb-tablet',
               '-nic', 'user,model=virtio-net-pci',
               '-drive', f'file={str(disk).replace(",", ",,")},format=qcow2,if=virtio']
    if no_reboot:
        command.append('-no-reboot')
    if qmp_path is not None:
        command += ['-qmp', f'unix:{qmp_path},server=on,wait=off']
    if firmware is not None:
        if mode != 'grub':
            raise RuntimeError('UEFI requires the GRUB image; direct boot is a recovery fallback')
        code, variables = firmware
        command += ['-drive', f'if=pflash,format=raw,unit=0,readonly=on,file={code}',
                    '-drive', f'if=pflash,format=raw,unit=1,file={variables}']
    if mode == 'direct':
        if kernel is None or initramfs is None:
            raise RuntimeError('Direct boot requires its saved kernel and initramfs')
        command += ['-kernel', str(kernel), '-initrd', str(initramfs), '-append',
                    'root=/dev/vda rw console=tty0 console=ttyS0,115200 '
                    'systemd.show_status=false panic=-1']
    elif mode != 'grub':
        raise RuntimeError('Unsupported VM boot mode')
    return command


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(10)
        try:
            self.socket.connect(str(path))
            self.stream = self.socket.makefile('rwb')
            greeting = json.loads(self.stream.readline())
            if 'QMP' not in greeting:
                raise RuntimeError('Missing QMP greeting')
            self.request_id = 0
            self.execute('qmp_capabilities')
        except Exception:
            self.close()
            raise

    def execute(self, name, arguments=None):
        self.request_id += 1
        request = {'execute': name, 'id': self.request_id}
        if arguments is not None:
            request['arguments'] = arguments
        self.stream.write(json.dumps(request).encode() + b'\n')
        self.stream.flush()
        while True:
            line = self.stream.readline()
            if not line:
                raise RuntimeError('QMP connection closed')
            reply = json.loads(line)
            if reply.get('id') != self.request_id:
                continue
            if 'error' in reply:
                raise RuntimeError(f'QMP failed: {reply["error"]}')
            if 'return' in reply:
                return reply['return']

    def close(self):
        if hasattr(self, 'stream'):
            self.stream.close()
        self.socket.close()

    def key(self, combination):
        self.execute('human-monitor-command', {'command-line': f'sendkey {combination}'})
        time.sleep(0.15)

    def type_ascii(self, text):
        for character in text:
            if not re.fullmatch('[a-z0-9 -]', character):
                raise ValueError('QA input is restricted to unambiguous US ASCII keys')
            self.key({' ': 'spc', '-': 'minus'}.get(character, character))

    def move(self, x, y):
        self.execute('input-send-event', {'events': [
            {'type': 'abs', 'data': {'axis': 'x', 'value': x}},
            {'type': 'abs', 'data': {'axis': 'y', 'value': y}},
        ]})
        time.sleep(0.3)

    def screenshot(self, path):
        safe_directory(path.parent, create=True)
        if os.path.lexists(path):
            safe_regular(path, writable=True)
        self.execute('screendump', {'filename': str(path), 'format': 'png'})
        image = read_regular(path)
        if image[:8] != b'\x89PNG\r\n\x1a\n' or len(image) < 24:
            raise RuntimeError('QEMU did not produce a PNG screenshot')
        return struct.unpack('>II', image[16:24])


def marker_command(marker):
    midpoint = marker.rfind('_') + 1
    return f"printf '\\n%s%s\\n' '{marker[:midpoint]}' '{marker[midpoint:]}'"


def terminal_text(text):
    # systemd emits OSC 3008 context annotations around console output. Keep
    # the raw diagnostic log, but recognise markers as visible terminal text.
    escapes = r'\x1b(?:\[[0-?]*[ -/]*[@-~]|[\]PX^_][\s\S]*?(?:\x07|\x1b\\)|[@-_])'
    return re.sub(escapes, '', text).replace('\r', '')


def open_guarded_log(path):
    safe_directory(path.parent, create=True)
    if os.path.lexists(path):
        safe_regular(path, writable=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise RuntimeError(f'Log must be a regular file without hardlinks: {path}')
        os.ftruncate(descriptor, 0)
        return os.fdopen(descriptor, 'wb')
    except Exception:
        os.close(descriptor)
        raise


def run_vm(command, headless, root=ROOT):
    if headless:
        print('NekoOS: вход в консоли — neko, пароль — neko.', flush=True)
        subprocess.run(command, check=True)
        return
    log = root / 'build/logs/arch-run.log'
    with open_guarded_log(log) as output:
        print('Открываю рабочий стол NekoOS. Пользователь и пароль: neko.\n'
              'Журнал запуска: build/logs/arch-run.log', flush=True)
        try:
            subprocess.run(command, stdin=subprocess.DEVNULL, stdout=output,
                           stderr=subprocess.STDOUT, check=True)
        except subprocess.CalledProcessError:
            raise RuntimeError(f'QEMU exited with an error; see {log}') from None


GUEST_HELPERS = r'''
desktop_environment() {
    export DISPLAY=:0 XAUTHORITY="$HOME/.Xauthority"
    session_pid=$(pgrep -u 1000 -x xfce4-session | head -n 1) || return 1
    test -n "$session_pid" && test -r "/proc/$session_pid/environ" || return 1
    while IFS= read -r -d '' entry; do
        case "$entry" in
            DISPLAY=*|XAUTHORITY=*|DBUS_SESSION_BUS_ADDRESS=*|XDG_RUNTIME_DIR=*) export "$entry" ;;
        esac
    done < "/proc/$session_pid/environ"
}
mapped_shell_window() {
    local class="$1" type="$2" minimum_width="$3" minimum_height="$4" window windows geometry
    local WIDTH HEIGHT X Y
    windows=$(xdotool search --onlyvisible --class "$class" 2>/dev/null) || return 1
    for window in $windows; do
        xprop -id "$window" _NET_WM_WINDOW_TYPE | grep -q "_NET_WM_WINDOW_TYPE_$type" || continue
        geometry=$(xdotool getwindowgeometry --shell "$window") || continue
        WIDTH=0 HEIGHT=0 X=-1 Y=-1
        eval "$geometry" || continue
        if [[ "$WIDTH:$HEIGHT:$X:$Y" =~ ^[0-9]+:[0-9]+:-?[0-9]+:-?[0-9]+$ ]] &&
           (( WIDTH >= minimum_width && HEIGHT >= minimum_height &&
              X >= 0 && Y >= 0 && X + WIDTH <= screen_width + 4 && Y + HEIGHT <= screen_height + 4 )); then
            return 0
        fi
    done
    return 1
}
arch_guest_diagnostics() {
    printf '\nARCH_GUEST_DIAGNOSTICS\n'
    id
    stat -c '%U:%G %a %n' /etc/sudoers.d /etc/sudoers.d/10-nekoos-wheel
    stat -c '%U:%G %a %n' "$HOME/.config" "$HOME/.config/xfce4" "$HOME/.config/xfce4/xfconf"
    ps -u 1000 -o pid,comm,stat,args
    systemctl status lightdm.service NetworkManager.service --no-pager
    desktop_environment
    wmctrl -m
    wmctrl -lx
    xrandr --current
    xprop -root _NET_CLIENT_LIST _NET_WORKAREA _NET_CURRENT_DESKTOP
    for window in $(xdotool search --onlyvisible --class 'xfce4-panel|xfdesktop' 2>/dev/null); do
        xprop -id "$window" _NET_WM_WINDOW_TYPE _NET_WM_STATE
        xdotool getwindowgeometry --shell "$window"
    done
    xfconf-query -c xfce4-panel -lv
    xfconf-query -c xfce4-desktop -lv
    for file in "$HOME/.xsession-errors" /var/log/lightdm/lightdm.log /var/log/Xorg.0.log; do
        if test -r "$file"; then printf '\n%s\n' "$file"; tail -n 80 "$file"; fi
    done
    journalctl --user -b --no-pager -n 60
    sudo -n /usr/bin/journalctl -b -u lightdm.service -u NetworkManager.service --no-pager -n 60
}
'''


class Guest:
    def __init__(self, command, log, timeout=480):
        self.command = command
        self.log = log
        self.timeout = timeout
        self.qmp = None
        self.process = None
        self.output = None

    def __enter__(self):
        self.output = open_guarded_log(self.log)
        try:
            self.process = subprocess.Popen(self.command, stdin=subprocess.PIPE,
                                            stdout=self.output, stderr=subprocess.STDOUT)
        except Exception:
            self.output.close()
            raise
        self.deadline = time.monotonic() + self.timeout
        return self

    def content(self):
        return terminal_text(self.log.read_text(errors='replace'))

    def wait(self, marker):
        while time.monotonic() < self.deadline:
            content = self.content()
            lines = content.splitlines()
            if 'ARCH_GUEST_FAILED' in lines or 'Kernel panic' in content:
                raise RuntimeError(f'Arch guest assertion failed; see {self.log}')
            if marker in lines:
                return
            if self.process.poll() is not None:
                raise RuntimeError(f'Arch guest exited before {marker}; see {self.log}')
            time.sleep(0.1)
        raise RuntimeError(f'Timed out waiting for {marker}; see {self.log}')

    def send(self, command):
        self.process.stdin.write(command.encode('utf-8') + b'\n')
        self.process.stdin.flush()

    def check(self, command, marker):
        script = ('set -euo pipefail\n' + GUEST_HELPERS +
                  "\ntrap 'status=$?; trap - ERR; set +e; arch_guest_diagnostics; exit \"$status\"' ERR\n" +
                  command + '\n' + marker_command(marker))
        self.send(f'bash -c {shlex.quote(script)} || ' + marker_command('ARCH_GUEST_FAILED'))
        self.wait(marker)

    def poweroff(self):
        self.send("printf 'neko\\n' | sudo -S -p '' /usr/bin/systemctl poweroff")
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError(f'Arch test deadline expired; see {self.log}')
        try:
            self.process.wait(timeout=min(40, remaining))
        except subprocess.TimeoutExpired:
            raise RuntimeError(f'Arch guest did not power off; see {self.log}') from None
        if self.process.returncode != 0 or 'Power down' not in self.content():
            raise RuntimeError(f'Arch guest did not shut down cleanly; see {self.log}')

    def __exit__(self, kind, error, traceback):
        if self.process is not None and self.process.poll() is None:
            if self.qmp is not None:
                try:
                    self.qmp.execute('system_powerdown')
                    self.process.wait(timeout=10)
                except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired):
                    pass
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        if self.qmp is not None:
            self.qmp.close()
        if self.process is not None:
            self.process.stdin.close()
        if self.output is not None:
            self.output.close()


CORE_CHECK = r'''
test "$(id -un)" = neko
test "$(id -u)" = 1000
test "$(cat /proc/1/comm)" = systemd
(source /etc/os-release; test "$ID" = nekoos; test "$ID_LIKE" = arch)
sudo -k
sudo_uid=$(printf 'neko\n' | sudo -S -p '' /usr/bin/id -u)
test "$sudo_uid" = 0
for directory in "$HOME/.config" "$HOME/.config/xfce4" "$HOME/.config/xfce4/xfconf"; do
    test -O "$directory"; test -w "$directory"
done
case "$(getconf GNU_LIBC_VERSION)" in glibc\ *) ;; *) exit 1 ;; esac
pacman -Q base base-devel linux glibc systemd gcc firefox thunar
firefox --version
mkdir -p "$HOME/.cache"
c_work=$(mktemp -d "$HOME/.cache/neko-c-check.XXXXXXXX")
printf '#include <stdio.h>\nint main(void) { puts("NEKO_ARCH_C_READY"); return sizeof(void*) == 8 ? 0 : 1; }\n' > "$c_work/main.c"
gcc -Wall -Wextra -Werror "$c_work/main.c" -o "$c_work/check"
c_output=$("$c_work/check")
test "$c_output" = NEKO_ARCH_C_READY
rm -r "$c_work"
attempt=0
while :; do
    if systemctl is-active --quiet lightdm.service NetworkManager.service &&
       pgrep -u 1000 -x xfce4-session >/dev/null &&
       pgrep -u 1000 -x xfce4-panel >/dev/null &&
       pgrep -u 1000 -x xfdesktop >/dev/null &&
       pgrep -u 1000 -x xfwm4 >/dev/null &&
       pgrep -u 1000 -x '[Tt]hunar' >/dev/null &&
       ip -4 route show default | grep -q '^default '; then break; fi
    attempt=$((attempt + 1))
    test "$attempt" -lt 90
    sleep 1
done
ip -4 route show default | grep -q '^default '
desktop_environment
read -r screen_width screen_height < <(xdotool getdisplaygeometry)
attempt=0
until mapped_shell_window '[Xx]fce4-panel' DOCK "$((screen_width / 2))" 16 &&
      mapped_shell_window '[Xx]fdesktop' DESKTOP "$((screen_width * 9 / 10))" "$((screen_height * 9 / 10))"; do
    attempt=$((attempt + 1))
    test "$attempt" -lt 90
    if (( attempt % 10 == 0 )); then printf 'ARCH_WAITING_FOR_VISIBLE_SHELL=%s\n' "$attempt"; wmctrl -lx; fi
    sleep 1
done
attempt=0
until wmctrl -xa Thunar; do
    attempt=$((attempt + 1))
    test "$attempt" -lt 30
    sleep 1
done
wmctrl -m
wmctrl -lx
curl --fail --silent --show-error --max-time 30 --output /dev/null https://archlinux.org/
'''


def test_desktop(root, verified, headless, uefi=False, timeout=480):
    images, hashes, mode = verified
    build = safe_directory(root / 'build/arch', create=True)
    previews = safe_directory(root / 'out/previews', create=True)
    logs = safe_directory(root / 'build/logs', create=True)
    digest = hashlib.sha256(NOTE.encode()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='arch-test-', dir=build) as directory:
        work = Path(directory)
        disk = work / 'system.qcow2'
        create_qcow(disk, images / 'system-template.img')
        if uefi and mode != 'grub':
            raise RuntimeError('UEFI test requires the GRUB image')
        passes = (False, False, True) if uefi else (False, False)
        for pass_number, use_uefi in enumerate(passes, 1):
            qmp_path = work / 'qmp.sock'
            qmp_path.unlink(missing_ok=True)
            command = qemu_command(disk, mode, images / 'vmlinuz-linux',
                                   images / 'initramfs-linux.img', headless, qmp_path,
                                   uefi_firmware(work) if use_uefi else None, no_reboot=True)
            log = logs / f'arch-test-{pass_number}.log'
            with Guest(command, log, timeout=timeout) as guest:
                try:
                    while not qmp_path.exists():
                        if guest.process.poll() is not None or time.monotonic() >= guest.deadline:
                            raise RuntimeError(f'QEMU did not open its control socket; see {log}')
                        time.sleep(0.1)
                    guest.qmp = QMP(qmp_path)
                    guest.wait('NEKO_ARCH_READY')
                    guest.send('stty -echo; set +o history; export PS1="neko$ "')
                    if pass_number > 1:
                        # Assert the previous boot's data before any test writes.
                        guest.check(f'test -d {FOLDER}\ntest -O {FOLDER}\n'
                                    f'test -O {FOLDER}/README.txt\n'
                                    f'checksum=$(sha256sum {FOLDER}/README.txt)\n'
                                    f'test "${{checksum%% *}}" = {digest}',
                                    'NEKO_ARCH_PERSISTENCE_READY')
                    else:
                        guest.check(f'test ! -e {FOLDER}', 'NEKO_ARCH_FRESH_READY')
                    guest.check(CORE_CHECK, 'NEKO_ARCH_DESKTOP_READY')
                    mice = guest.qmp.execute('query-mice')
                    if not any(mouse['current'] and mouse['absolute'] for mouse in mice):
                        raise RuntimeError('QEMU USB tablet is not an active absolute pointer')
                    width, height = guest.qmp.screenshot(previews / 'arch-desktop.png')
                    if pass_number == 1:
                        guest.qmp.move(30000, 25000)
                        expected_x = 30000 * (width - 1) // 32767
                        expected_y = 25000 * (height - 1) // 32767
                        guest.check('desktop_environment\n'
                                    'eval "$(xdotool getmouselocation --shell)"\n'
                                    f'dx=$((X - {expected_x})); dy=$((Y - {expected_y}))\n'
                                    'test "$dx" -ge -4; test "$dx" -le 4\n'
                                    'test "$dy" -ge -4; test "$dy" -le 4',
                                    'NEKO_ARCH_POINTER_READY')
                        guest.qmp.key('ctrl-shift-n')
                        time.sleep(0.7)
                        guest.qmp.key('ctrl-a')
                        guest.qmp.type_ascii('neko-gui-check')
                        guest.qmp.key('ret')
                        guest.check(f'attempt=0\nwhile ! test -d {FOLDER}; do\n'
                                    'attempt=$((attempt + 1)); test "$attempt" -lt 20; sleep 1\ndone\n'
                                    f'test -O {FOLDER}\n'
                                    f'printf %s {shlex.quote(NOTE)} > {FOLDER}/README.txt\n'
                                    f'checksum=$(sha256sum {FOLDER}/README.txt)\n'
                                    f'test "${{checksum%% *}}" = {digest}',
                                    'NEKO_ARCH_GUI_FOLDER_READY')
                    guest.qmp.screenshot(previews / 'arch-desktop.png')
                    guest.qmp.screenshot(previews / f'arch-desktop-boot-{pass_number}.png')
                    if pass_number == 1:
                        guest.check('desktop_environment\n'
                                    'nohup firefox --no-remote about:blank '
                                    '> "$HOME/.cache/neko-firefox-check.log" 2>&1 < /dev/null &\n'
                                    'attempt=0\n'
                                    'until wmctrl -lx | grep -qi firefox; do\n'
                                    'attempt=$((attempt + 1)); test "$attempt" -lt 60; sleep 1\ndone\n'
                                    'wmctrl -xa Firefox', 'NEKO_ARCH_BROWSER_READY')
                        time.sleep(1)
                        guest.qmp.screenshot(previews / 'arch-browser.png')
                        guest.qmp.key('ctrl-q')
                    guest.poweroff()
                except Exception:
                    if guest.qmp is not None and guest.process.poll() is None:
                        try:
                            guest.qmp.screenshot(previews / 'arch-desktop-failed.png')
                        except (OSError, RuntimeError, ValueError):
                            pass
                    raise
    print('ARCH_DESKTOP_TEST_PASSED: normal neko account, glibc/systemd/pacman, GCC, '
          'Xfce/Thunar/Firefox, guest HTTPS, physical USB pointer/keyboard and two-boot file persistence' +
          ('; additional UEFI boot passed' if uefi else ''))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('run', 'test'))
    parser.add_argument('--no-build', action='store_true', help='require existing verified images')
    parser.add_argument('--headless', action='store_true', help='hide the QEMU window')
    parser.add_argument('--uefi', action='store_true',
                        help='run with private UEFI firmware, or add a third UEFI test boot')
    parser.add_argument('--timeout', type=int, default=480,
                        help='seconds per test boot including its checks (default: 480)')
    args = parser.parse_args(argv)
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if sys.platform != 'linux' or os.geteuid() == 0:
        parser.error('run as a regular Linux / WSL2 user')
    if str(ROOT).startswith('/mnt/'):
        parser.error('use the Linux workspace copy, not a Windows-mounted directory')
    for tool in ('qemu-img', 'qemu-system-x86_64'):
        if shutil.which(tool) is None:
            raise RuntimeError(f'Missing host tool: {tool}')
    lock_path = (ROOT / 'build/arch/.test.lock' if args.action == 'test'
                 else ROOT / 'out/arch/disks/.run-lock')
    with file_lock(lock_path):
        if args.action == 'run':
            print('Подготавливаю запуск NekoOS…', flush=True)
        ensure_images(ROOT, args.no_build)
        with file_lock(ROOT / 'build/arch/.build.lock', shared=True):
            verified = verify_images(ROOT)
            if args.action == 'test':
                test_desktop(ROOT, verified, args.headless, args.uefi, args.timeout)
            else:
                disk, mode, kernel, initramfs = prepare_persistent(ROOT, verified)
                if mode == 'direct':
                    print('Arch VM uses the explicit direct-boot fallback; GRUB is unavailable.',
                          flush=True)
                if args.uefi:
                    with tempfile.TemporaryDirectory(prefix='arch-run-', dir=ROOT / 'build/arch') as directory:
                        firmware = uefi_firmware(Path(directory))
                        run_vm(qemu_command(disk, mode, kernel, initramfs,
                                            args.headless, firmware=firmware), args.headless, ROOT)
                else:
                    run_vm(qemu_command(disk, mode, kernel, initramfs, args.headless), args.headless, ROOT)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f'ARCH_VM_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
