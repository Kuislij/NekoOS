#!/usr/bin/env python3
"""Verify, run and boot-test the NekoOS live ISO without using user VM disks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arch_vm as vm

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('nekoos-live-x86_64.iso', 'packages.lock', 'build-info.json', 'archiso-version.txt', 'boot-modes.txt')
MODES = ('bios-cd', 'uefi-cd', 'bios-usb', 'uefi-usb')


def verify_iso(root=ROOT):
    directory = vm.safe_directory(root / 'out/arch/iso')
    manifest = vm.read_regular(directory / 'SHA256SUMS').decode('ascii')
    hashes = {}
    if not manifest.endswith('\n'):
        raise RuntimeError('ISO manifest must end with a newline')
    for line in manifest[:-1].split('\n'):
        match = re.fullmatch(r'([0-9a-f]{64})  ([a-z][a-z0-9_.-]*)', line)
        if match is None or match[2] not in NAMES or match[2] in hashes:
            raise RuntimeError('Malformed, duplicate or unsafe ISO manifest entry')
        hashes[match[2]] = match[1]
    if set(hashes) != set(NAMES):
        raise RuntimeError('Incomplete ISO manifest')
    for name in NAMES:
        if vm.sha256_file(directory / name) != hashes[name]:
            raise RuntimeError(f'ISO checksum verification failed: {name}')
    if vm.read_regular(directory / 'boot-modes.txt').decode() != ''.join(mode + '\n' for mode in MODES):
        raise RuntimeError('Unexpected ISO boot modes')
    info = json.loads(vm.read_regular(directory / 'build-info.json'))
    if not isinstance(info, dict) or info.get('format') != 1 or info.get('live_persistence') is not False:
        raise RuntimeError('Invalid live ISO metadata')
    return directory / NAMES[0], info


def qemu_command(iso, headless=False, usb=False, firmware=None, qmp=None, probe=None, test=False):
    quote = lambda value: str(value).replace(',', ',,')
    command = ['qemu-system-x86_64', '-machine', 'q35', *vm.acceleration(),
               '-m', '3072M', '-smp', '2', '-nodefaults', '-monitor', 'none', '-serial', 'stdio',
               '-display', 'none' if headless else 'gtk', '-device', 'virtio-vga',
               '-device', 'qemu-xhci', '-device', 'usb-kbd', '-device', 'usb-tablet',
               '-nic', 'user,model=virtio-net-pci']
    if test:
        command.append('-no-reboot')
    if usb:
        command += ['-drive', f'if=none,id=live,file={quote(iso)},format=raw,readonly=on',
                    '-device', 'usb-storage,drive=live,removable=on,bootindex=1']
    else:
        command += ['-drive', f'file={quote(iso)},format=raw,media=cdrom,readonly=on', '-boot', 'order=d']
    if probe is not None:
        command += ['-drive', f'file={quote(probe)},format=raw,if=virtio']
    if firmware is not None:
        code, variables = firmware
        command += ['-drive', f'if=pflash,format=raw,unit=0,readonly=on,file={quote(code)}',
                    '-drive', f'if=pflash,format=raw,unit=1,file={quote(variables)}']
    if qmp is not None:
        command += ['-qmp', f'unix:{qmp},server=on,wait=off']
    return command


LIVE_CHECK = r'''
test "$(cat /usr/share/nekoos/live-mode)" = ephemeral-live
test "$(findmnt -n -o FSTYPE /)" = overlay
grep -q 'archisobasedir=neko' /proc/cmdline
test ! -e "$HOME/neko-live-check"
test "$(printf 'neko\n' | sudo -S -p '' blkid -s LABEL -o value /dev/vda)" = NEKO_ISO_PROBE
if findmnt -rn -S /dev/vda | grep -q .; then exit 1; fi
test "$(systemctl is-enabled sshd.service 2>/dev/null || true)" = masked
systemctl is-active --quiet neko-live-font-cache.service
test "$(systemctl show -p Result --value neko-live-font-cache.service)" = success
'''


def test_iso(iso, headless, timeout, root=ROOT):
    build = vm.safe_directory(root / 'build/archiso', create=True)
    logs = vm.safe_directory(root / 'build/logs', create=True)
    previews = vm.safe_directory(root / 'out/previews', create=True)
    iso_hash = vm.sha256_file(iso)
    with vm.open_guarded_log(logs / 'arch-iso-test-summary.json') as stream:
        stream.write((json.dumps({'result': 'running', 'iso_sha256': iso_hash}) + '\n').encode())
    with tempfile.TemporaryDirectory(prefix='live-test-', dir=build) as temporary:
        work = Path(temporary)
        probe = work / 'internal-probe.img'
        # A generated regular file only. This test intentionally permits guest
        # writes so a hash mismatch can detect an accidental internal-disk mount.
        with probe.open('xb') as stream:
            stream.truncate(64 * 1024 * 1024)
        subprocess.run(['mkfs.ext4', '-F', '-q', '-m', '0', '-L', 'NEKO_ISO_PROBE', str(probe)], check=True)
        before = vm.sha256_file(probe)
        for mode in MODES:
            firmware = vm.uefi_firmware(work) if mode.startswith('uefi') else None
            qmp_path = work / 'qmp.sock'
            qmp_path.unlink(missing_ok=True)
            command = qemu_command(iso, headless, mode.endswith('usb'), firmware, qmp_path, probe, test=True)
            log = logs / f'arch-iso-test-{mode}.log'
            print(f'Проверяю Live ISO: {mode}', flush=True)
            with vm.Guest(command, log, timeout=timeout) as guest:
                try:
                    while not qmp_path.exists():
                        if guest.process.poll() is not None or time.monotonic() >= guest.deadline:
                            raise RuntimeError(f'No ISO QMP socket; see {log}')
                        time.sleep(0.1)
                    guest.qmp = vm.QMP(qmp_path)
                    guest.wait('NEKO_ARCH_READY')
                    guest.send('stty -echo; set +o history; export PS1="neko$ "')
                    guest.check(LIVE_CHECK, 'NEKO_LIVE_ROOT_READY')
                    guest.check(vm.CORE_CHECK, 'NEKO_LIVE_DESKTOP_READY')
                    guest.check('test -s /usr/share/licenses/nekoos-archiso-templates/LICENSE\n'
                                'test -s /usr/share/licenses/nekoos-archiso-templates/AUTHORS.rst\n'
                                'attempt=0\nwhile ! test -e "$HOME/.config/nekoos/desktop-initialized"; do\n'
                                'attempt=$((attempt+1)); test "$attempt" -lt 30; sleep 1\ndone\nsleep 1\n'
                                'if journalctl --user -b --no-pager | grep "glycin-svg.*dumped core" >/dev/null; then exit 1; fi',
                                'NEKO_LIVE_WALLPAPER_READY')
                    mice = guest.qmp.execute('query-mice')
                    if not any(mouse['current'] and mouse['absolute'] for mouse in mice):
                        raise RuntimeError('Live USB tablet is not an active absolute pointer')
                    width, height = guest.qmp.screenshot(previews / f'arch-live-{mode}.png')
                    guest.qmp.move(30000, 25000)
                    x, y = 30000 * (width - 1) // 32767, 25000 * (height - 1) // 32767
                    guest.check('desktop_environment\neval "$(xdotool getmouselocation --shell)"\n'
                                f'dx=$((X-{x})); dy=$((Y-{y}))\n'
                                'test "$dx" -ge -4; test "$dx" -le 4\n'
                                'test "$dy" -ge -4; test "$dy" -le 4', 'NEKO_LIVE_POINTER_READY')
                    guest.qmp.key('ctrl-shift-n')
                    time.sleep(0.7)
                    guest.qmp.type_ascii('neko-live-check')
                    guest.qmp.key('ret')
                    guest.check('attempt=0\nwhile ! test -d "$HOME/neko-live-check"; do\n'
                                'attempt=$((attempt+1)); test "$attempt" -lt 20; sleep 1\ndone\n'
                                'test -O "$HOME/neko-live-check"\n'
                                'printf "Live data is temporary\\n" > "$HOME/neko-live-check/note.txt"',
                                'NEKO_LIVE_KEYBOARD_READY')
                    guest.qmp.screenshot(previews / f'arch-live-{mode}.png')
                    guest.poweroff()
                except Exception:
                    if guest.qmp is not None and guest.process.poll() is None:
                        try:
                            guest.qmp.screenshot(previews / 'arch-live-failed.png')
                        except (OSError, RuntimeError, ValueError):
                            pass
                    raise
            if vm.sha256_file(probe) != before:
                raise RuntimeError(f'Live {mode} changed the test internal disk')
            if firmware is not None:
                (work / 'OVMF_VARS.fd').unlink()
        summary = {'result': 'passed', 'iso_sha256': iso_hash,
                   'boot_modes': list(MODES), 'internal_probe_sha256': before,
                   'internal_disk_unchanged': True, 'live_state_reset_between_boots': True}
        with vm.open_guarded_log(logs / 'arch-iso-test-summary.json') as stream:
            stream.write((json.dumps(summary, indent=2) + '\n').encode())
    print('NEKO_LIVE_ISO_TEST_PASSED: BIOS/UEFI CD+USB, desktop/input/HTTPS/GCC, ephemeral home, untouched internal disk')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('verify', 'run', 'test'))
    parser.add_argument('--no-build', action='store_true')
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--uefi', action='store_true')
    parser.add_argument('--usb', action='store_true')
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args(argv)
    if sys.platform != 'linux' or os.geteuid() == 0 or str(ROOT).startswith('/mnt/'):
        parser.error('use a regular user in the native Linux workspace')
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if args.action == 'test' and (args.uefi or args.usb):
        parser.error('ISO test always checks both firmwares and both media types')
    build = vm.safe_directory(ROOT / 'build/archiso', create=True)
    # Same lock as publication: do not replace an ISO while QEMU reads it.
    if not os.path.lexists(ROOT / 'out/arch/iso'):
        if args.no_build or args.action == 'verify':
            raise RuntimeError('Live ISO is missing; run bash os arch iso build')
        subprocess.run(['bash', str(ROOT / 'scripts/arch-iso-build.sh')], check=True)
    with vm.file_lock(ROOT / 'build/arch/.build.lock', shared=True):
        iso, _ = verify_iso()
        if args.action == 'verify':
            print('NEKO_LIVE_ISO_VERIFIED')
            return
        for tool in ('qemu-system-x86_64', 'mkfs.ext4'):
            if shutil.which(tool) is None:
                raise RuntimeError(f'Missing host tool: {tool}')
        with vm.file_lock(build / '.vm.lock'):
            if args.action == 'test':
                test_iso(iso, args.headless, args.timeout)
            else:
                print('NekoOS Live: файлы сеанса временные; пользователь и пароль — neko.', flush=True)
                with tempfile.TemporaryDirectory(prefix='live-run-', dir=build) as directory:
                    firmware = vm.uefi_firmware(Path(directory)) if args.uefi else None
                    vm.run_vm(qemu_command(iso, args.headless, args.usb, firmware), args.headless, ROOT)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f'NEKO_LIVE_ISO_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
