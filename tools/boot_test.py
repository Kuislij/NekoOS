#!/usr/bin/env python3
"""Boot the actual guest, exercise its shell, and require clean poweroff."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-build', action='store_true', help='test existing images')
    parser.add_argument('--timeout', type=int, default=90, help='boot deadline in seconds')
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if sys.platform != 'linux' or os.geteuid() == 0:
        parser.error('run as a regular Linux / WSL2 user')
    import fcntl
    (ROOT / 'build').mkdir(exist_ok=True)
    with (ROOT / 'build/.boot-test.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another boot test is already running') from None
        return boot(args)


def boot(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)
    log = ROOT / 'build/logs/boot-test.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    command = [
        'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg',
        '-cpu', 'qemu64', '-m', '256M', '-smp', '1', '-nodefaults',
        '-display', 'none', '-monitor', 'none', '-serial', 'stdio',
        '-nic', 'none', '-no-reboot',
        '-kernel', str(images / 'bzImage'),
        '-initrd', str(images / 'initramfs.cpio.gz'),
        '-append', 'console=ttyS0,115200 rdinit=/init panic=-1',
    ]
    with log.open('wb') as output:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output,
                                   stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + args.timeout
            sent_exit = False
            sent = False
            while time.monotonic() < deadline:
                content = log.read_text(errors='replace')
                lines = content.replace('\r', '').splitlines()
                shells_started = content.count('built-in shell (ash)')
                if 'SYSTEM_READY' in lines and shells_started >= 1 and not sent_exit:
                    process.stdin.write(b'exit\n')
                    process.stdin.flush()
                    sent_exit = True
                if sent_exit and shells_started >= 2 and not sent:
                    # Split the marker so terminal echo cannot count as a passing test.
                    process.stdin.write(
                        b"test -L /bin && test -x /usr/bin/busybox && "
                        b"test -d /var/lib && test -d /usr/local/bin && "
                        b"test -r /proc/version && test -d /sys/kernel && "
                        b"test -c /dev/console && test -c /dev/pts/ptmx && "
                        b"echo neko-test > /tmp/smoke && "
                        b"test \"$(cat /tmp/smoke)\" = neko-test && "
                        b"uname -r && cat /etc/os-release && neko-help && "
                        b"printf '\\n%s%s\\n' 'SHELL_' 'READY' && poweroff\n"
                    )
                    process.stdin.flush()
                    sent = True
                code = process.poll()
                if code is not None:
                    # Re-read after exit: the last serial output may arrive during poll.
                    lines = log.read_text(errors='replace').replace('\r', '').splitlines()
                    if code == 0 and sent and 'SHELL_READY' in lines and any(
                        'Power down' in line for line in lines
                    ):
                        print(f'BOOT_TEST_PASSED: init, shell, filesystems, poweroff. Log: {log}')
                        return 0
                    raise RuntimeError(f'QEMU exited with code {code} before a complete boot test')
                if any(marker in content for marker in (
                    'Kernel panic', 'BOOT_FAILED:', 'Failed to execute /init'
                )):
                    raise RuntimeError('Guest boot failed')
                time.sleep(0.1)
            raise RuntimeError(f'Guest did not complete boot and poweroff in {args.timeout}s')
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            process.stdin.close()


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'BOOT_TEST_FAILED: {error}', file=sys.stderr)
        print(f'See {ROOT / "build/logs/boot-test.log"}', file=sys.stderr)
        sys.exit(1)
