#!/usr/bin/env python3
"""Update an offline writable system disk, retaining an atomic rollback image."""
import argparse
from contextlib import ExitStack
import fcntl
import os
from pathlib import Path
import platform
import re
import secrets
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BACKUP_NAME = re.compile(r'system-backup-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{8}\.img\Z')


def run(command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def regular_file(path):
    if path.is_symlink() or not path.is_file():
        raise RuntimeError(f'Missing or unsafe regular file: {path}')


def verify_disk(path):
    regular_file(path)
    for field, expected in (('TYPE', 'ext4'), ('LABEL', 'NEKO_SYSTEM')):
        actual = subprocess.check_output(
            ['blkid', '-p', '-s', field, '-o', 'value', str(path)], text=True
        ).strip()
        if actual != expected:
            raise RuntimeError(f'Wrong system disk {field}: {path}')


def verify_images(images):
    for name in ('bzImage', 'initramfs.cpio.gz', 'bootstrap.cpio.gz',
                 'system-template.img', 'SHA256SUMS'):
        regular_file(images / name)
    run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, stdout=subprocess.DEVNULL)
    run([sys.executable, str(ROOT / 'tools/validate_image.py'),
         str(images / 'initramfs.cpio.gz')], stdout=subprocess.DEVNULL)


def check_filesystem(path):
    result = subprocess.run(['e2fsck', '-f', '-p', str(path)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                            text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(f'Filesystem check failed for {path}: {result.stderr.strip()}')


def fsync_directory(directory):
    descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def new_backup_path(directory):
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    return directory / f'system-backup-{stamp}-{secrets.token_hex(4)}.img'


def make_candidate(source):
    descriptor, filename = tempfile.mkstemp(prefix='system-candidate-', suffix='.img',
                                           dir=source.parent)
    os.close(descriptor)
    candidate = Path(filename)
    try:
        run(['cp', '--reflink=auto', '--sparse=always', '--', str(source),
             str(candidate)])
        return candidate
    except BaseException:
        candidate.unlink(missing_ok=True)
        raise


def run_maintenance(images, candidate, log, timeout=120):
    command = [
        'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'qemu64',
        '-m', '256M', '-smp', '2', '-nodefaults', '-display', 'none',
        '-monitor', 'none', '-serial', 'stdio', '-nic', 'none', '-no-reboot',
        '-drive', f'file={candidate},format=raw,if=virtio',
        '-kernel', str(images / 'bzImage'),
        '-initrd', str(images / 'initramfs.cpio.gz'),
        '-append', 'console=ttyS0,115200 rdinit=/neko-update panic=-1 neko.update=required',
    ]
    with log.open('wb') as output:
        try:
            run(command, stdin=subprocess.DEVNULL, stdout=output,
                stderr=subprocess.STDOUT, timeout=timeout)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            raise RuntimeError(f'Update guest failed; see {log}') from error
    lines = log.read_text(errors='replace').replace('\r', '').splitlines()
    if ('SYSTEM_UPDATE_APPLIED' not in lines or
            any(line.startswith('SYSTEM_UPDATE_FAILED:') for line in lines) or
            not any('Power down' in line for line in lines)):
        raise RuntimeError(f'Update guest did not finish cleanly; see {log}')


def verify_guest_boot(images, candidate, timeout=120):
    # This disposable data disk keeps the user's state.img completely out of QEMU.
    from boot_test import run_disk_guest

    with tempfile.TemporaryDirectory(prefix='neko-update-state-', dir=candidate.parent) as temporary:
        state_disk = Path(temporary) / 'state.img'
        run(['qemu-img', 'create', '-f', 'raw', str(state_disk), '128M'],
            stdout=subprocess.DEVNULL)
        run(['mkfs.ext4', '-F', '-q', str(state_disk)], stdout=subprocess.DEVNULL)
        run_disk_guest(
            images, state_disk,
            b'test -x /usr/bin/neko-help && test -x /usr/bin/tcc && '
            b'test -f /etc/os-release && '
            b"printf '\\n%s%s\\n' 'SYSTEM_UPDATE_BOOT_' 'OK' && poweroff || poweroff\n",
            'SYSTEM_UPDATE_BOOT_OK', 1, timeout, False,
            log_prefix='system-update-boot', system_disk=candidate,
        )


def replace_with_backup(disk, candidate):
    backup = new_backup_path(disk.parent)
    os.link(disk, backup)
    fsync_directory(disk.parent)
    try:
        os.replace(candidate, disk)
        fsync_directory(disk.parent)
    except BaseException:
        # The old disk remains usable; the backup is also kept for inspection.
        raise
    return backup


def apply_update(images, disk, logs):
    verify_disk(disk)
    verify_images(images)
    candidate = make_candidate(disk)
    try:
        check_filesystem(candidate)
        run_maintenance(images, candidate, logs / 'system-update.log')
        verify_disk(candidate)
        check_filesystem(candidate)
        verify_guest_boot(images, candidate)
        check_filesystem(candidate)
        backup = replace_with_backup(disk, candidate)
        print(f'SYSTEM_UPDATE_READY: {disk}')
        print(f'SYSTEM_BACKUP: {backup}')
        return backup
    finally:
        candidate.unlink(missing_ok=True)


def rollback_update(disk, backup):
    verify_disk(disk)
    verify_disk(backup)
    candidate = make_candidate(backup)
    try:
        check_filesystem(candidate)
        previous = replace_with_backup(disk, candidate)
        print(f'SYSTEM_ROLLBACK_READY: {disk}')
        print(f'SYSTEM_BACKUP: {previous}')
        return previous
    finally:
        candidate.unlink(missing_ok=True)


def lock(stack, path):
    handle = stack.enter_context(path.open('a+b'))
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError(f'Another build, update or VM is using {path.name}') from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest='command', required=True)
    apply_parser = subparsers.add_parser('apply', help='build and update the system disk')
    apply_parser.add_argument('--no-build', action='store_true',
                              help='use already built, checksum-verified images')
    rollback_parser = subparsers.add_parser('rollback', help='restore a named backup')
    rollback_parser.add_argument('backup', help='backup filename printed by system-update')
    args = parser.parse_args()
    if platform.system() != 'Linux' or platform.machine() != 'x86_64' or os.geteuid() == 0:
        parser.error('run as a regular x86_64 Linux / WSL2 user')
    if str(ROOT).startswith('/mnt/'):
        parser.error('use the Linux filesystem, not /mnt/')
    disks = ROOT / 'out/disks'
    images = ROOT / 'out/images'
    logs = ROOT / 'build/logs'
    for directory in (disks, images, logs):
        if directory.is_symlink():
            raise RuntimeError(f'Unsafe directory: {directory}')
        directory.mkdir(parents=True, exist_ok=True)
    disk = disks / 'system.img'
    with ExitStack() as stack:
        lock(stack, disks / '.run-lock')
        lock(stack, disks / '.system-create-lock')
        lock(stack, disks / '.system-update-lock')
        if args.command == 'apply':
            verify_disk(disk)
            if not args.no_build:
                run(['bash', str(ROOT / 'scripts/build.sh')])
            lock(stack, ROOT / 'build/.lock')
            apply_update(images, disk, logs)
        else:
            if not BACKUP_NAME.fullmatch(args.backup):
                parser.error('backup must be the exact system-backup-...img filename')
            rollback_update(disk, disks / args.backup)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'SYSTEM_UPDATE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
