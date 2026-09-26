#!/usr/bin/env python3
"""Boot the actual guest, exercise its shell, and require clean poweroff."""
import argparse
import fcntl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
import time
from threading import Thread

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--no-build', action='store_true', help='test existing images')
    parser.add_argument('--disk', action='store_true', help='verify persistence across two boots')
    parser.add_argument('--iso', action='store_true', help='boot the persistent VM through BIOS and GRUB')
    parser.add_argument('--net', action='store_true', help='verify DHCP, loopback and HTTP over virtio-net')
    parser.add_argument('--package', action='store_true', help='install and remove a package on a disposable disk')
    parser.add_argument('--services', action='store_true', help='verify persistent service settings on a disposable disk')
    parser.add_argument('--system', action='store_true', help='boot a writable system root across two boots')
    parser.add_argument('--timeout', type=int, default=90, help='boot deadline in seconds')
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if args.iso and not args.system:
        args.disk = True
    if args.net and args.disk:
        parser.error('--net test uses a temporary VM; do not combine it with --disk or --iso')
    if args.package and (args.disk or args.iso or args.net):
        parser.error('--package cannot be combined with --disk, --iso or --net')
    if args.services and (args.disk or args.iso or args.net or args.package):
        parser.error('--services cannot be combined with other test modes')
    if args.system and (args.disk or args.net or args.package or args.services):
        parser.error('--system cannot be combined with other test modes')
    if sys.platform != 'linux' or os.geteuid() == 0:
        parser.error('run as a regular Linux / WSL2 user')
    (ROOT / 'build').mkdir(exist_ok=True)
    if args.system:
        lock_name = '.system-test.lock'
    elif args.services:
        lock_name = '.services-test.lock'
    elif args.package:
        lock_name = '.package-test.lock'
    elif args.net:
        lock_name = '.network-test.lock'
    elif args.disk:
        lock_name = '.disk-test.lock'
    else:
        lock_name = '.boot-test.lock'
    with (ROOT / 'build' / lock_name).open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another boot test is already running') from None
        if args.system:
            return boot_system(args)
        if args.services:
            return boot_services(args)
        if args.package:
            return boot_package(args)
        if args.net:
            return boot_network(args)
        if args.disk:
            return boot_disk(args)
        return boot(args)


def boot_network(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)

    class LocalHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != '/check':
                self.send_error(404)
                return
            payload = b'NEKO_NETWORK_READY\n'
            self.server.served = True
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), LocalHandler)
    server.served = False
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    log = ROOT / 'build/logs/network-test.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    command = [
        'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg',
        '-cpu', 'qemu64', '-m', '256M', '-smp', '2', '-nodefaults',
        '-display', 'none', '-monitor', 'none', '-serial', 'stdio',
        '-nic', 'user,model=virtio-net-pci,ipv6=off', '-no-reboot',
        '-kernel', str(images / 'bzImage'),
        '-initrd', str(images / 'initramfs.cpio.gz'),
        '-append', 'console=ttyS0,115200 rdinit=/init panic=-1',
    ]
    try:
        with log.open('wb') as output:
            process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                       stdout=output, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + args.timeout
                sent = False
                while time.monotonic() < deadline:
                    content = log.read_text(errors='replace')
                    lines = content.replace('\r', '').splitlines()
                    if ('NETWORK_READY' in lines and 'SYSTEM_READY' in lines
                            and 'built-in shell (ash)' in content and not sent):
                        checks = [
                            b'neko-service restart network',
                            b'neko-service status network',
                            b'neko-net-status',
                            b"ifconfig eth0 | grep -Fq '10.0.2.'",
                            b"route -n | grep -Fq '10.0.2.2'",
                            b"grep -Fqx 'nameserver 10.0.2.3' /etc/resolv.conf",
                            b'ping -c 1 -W 2 127.0.0.1 > /tmp/ping.log',
                            f'wget -q -O /tmp/network.txt http://10.0.2.2:{port}/check'.encode(),
                            b'test "$(cat /tmp/network.txt)" = NEKO_NETWORK_READY',
                            b"printf '\\n%s%s\\n' 'NETWORK_TEST_' 'PASSED'",
                        ]
                        guest_command = b' && '.join(checks) + b' && poweroff || poweroff\n'
                        process.stdin.write(guest_command)
                        process.stdin.flush()
                        sent = True
                    code = process.poll()
                    if code is not None:
                        lines = log.read_text(errors='replace').replace('\r', '').splitlines()
                        if (code == 0 and sent and server.served
                                and 'NETWORK_TEST_PASSED' in lines
                                and any('Power down' in line for line in lines)):
                            print(f'NETWORK_TEST_PASSED: DHCP, DNS config, ICMP, HTTP. Log: {log}')
                            return 0
                        raise RuntimeError(f'Network boot failed; see {log}')
                    if 'Kernel panic' in content or 'BOOT_FAILED:' in content:
                        raise RuntimeError(f'Network boot failed; see {log}')
                    time.sleep(0.1)
                raise RuntimeError(f'Network boot timed out; see {log}')
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                process.stdin.close()
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


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
        '-cpu', 'qemu64', '-m', '256M', '-smp', '2', '-nodefaults',
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
                        b"neko-service list | grep -Fqx network && "
                        b"neko-service status network && "
                        b"if neko-service disable network; then false; else true; fi && "
                        b"test -r /proc/version && test -d /sys/kernel && "
                        b"test -c /dev/console && test -c /dev/pts/ptmx && "
                        b"echo neko-test > /tmp/smoke && "
                        b"test \"$(cat /tmp/smoke)\" = neko-test && "
                        b"printf '%s\\n' '#include <stdio.h>' "
                        b"'int main(void) { puts(\"C_\" \"READY\"); return 0; }' "
                        b"> /tmp/hello.c && "
                        b"cc /tmp/hello.c -o /tmp/hello && /tmp/hello && "
                        b"cc /usr/share/nekoos/examples/hello.c -o /tmp/example && "
                        b"/tmp/example && "
                        b"uname -r && cat /etc/os-release && neko-help && "
                        b"neko-boot-status && "
                        b"printf '\\n%s%s\\n' 'SHELL_' 'READY' && poweroff || poweroff\n"
                    )
                    process.stdin.flush()
                    sent = True
                code = process.poll()
                if code is not None:
                    # Re-read after exit: the last serial output may arrive during poll.
                    lines = log.read_text(errors='replace').replace('\r', '').splitlines()
                    if (code == 0 and sent and 'SHELL_READY' in lines
                            and 'C_READY' in lines and 'HARDWARE_READY' in lines
                            and 'Hello from NekoOS' in lines
                            and any('Power down' in line for line in lines)):
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


def boot_disk(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)
    if args.iso:
        if not args.no_build:
            subprocess.run(['bash', str(ROOT / 'scripts/create-iso.sh')], check=True)
        subprocess.run(['sha256sum', '-c', 'ISO_SHA256SUMS'], cwd=images, check=True)
    subprocess.run(['bash', str(ROOT / 'scripts/create-disk.sh')], check=True)
    disk = ROOT / 'out/disks/state.img'
    if disk.is_symlink() or not disk.is_file():
        raise RuntimeError('Virtual disk is missing or is a symlink')
    token = secrets.token_hex(12)
    state_files = [f'{directory}/.nekoos-persistence-test-{token}'
                   for directory in ('/root', '/home', '/var/lib')]
    program_name = f'neko-test-{token}'
    program_path = f'/usr/local/bin/{program_name}'
    write = (
        'test "$PWD" = /root && '
        + ' && '.join(f"printf '%s' '{token}' > {path}" for path in state_files)
        + " && printf '%s\\n' '#include <stdio.h>' "
        + f"'int main(void) {{ puts(\"{token}\"); return 0; }}' > /tmp/local-program.c"
        + f' && cc /tmp/local-program.c -o {program_path}'
        + " && sync && printf '\\n%s%s\\n' 'WRITE_' 'OK' && poweroff\n"
    ).encode('ascii')
    verify = (
        ' && '.join(f'test "$(cat {path})" = "{token}"' for path in state_files)
        + f' && test "$(command -v {program_name})" = "{program_path}"'
        + f' && test "$({program_name})" = "{token}"'
        + " && printf '\\n%s%s\\n' 'PERSISTENCE_' 'OK' && "
        + ' && '.join(f'rm {path}' for path in state_files)
        + f' && rm {program_path}'
        + ' && sync && poweroff\n'
    ).encode('ascii')
    with (ROOT / 'out/disks/.run-lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('This NekoOS virtual disk is already in use') from None
        run_disk_guest(images, disk, write, 'WRITE_OK', 1, args.timeout, args.iso)
        run_disk_guest(images, disk, verify, 'PERSISTENCE_OK', 2, args.timeout, args.iso)
    print(('ISO_BOOT_TEST_PASSED' if args.iso else 'DISK_TEST_PASSED')
          + ': data survived poweroff and the next boot')
    return 0


def boot_package(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)
    demo = '/usr/share/nekoos/packages/neko-greet-0.1.0.npkg'
    newer = '/usr/share/nekoos/packages/neko-greet-0.2.0.npkg'
    newest = '/usr/share/nekoos/packages/neko-greet-0.3.0.npkg'
    companion = '/usr/share/nekoos/packages/neko-companion-1.0.0.npkg'
    install = (
        f'neko-pkg info {demo} | grep -Fqx name=neko-greet && '
        f'head -c 64 {demo} > /tmp/broken.npkg && '
        'if neko-pkg install /tmp/broken.npkg; then false; else true; fi && '
        "printf personal > /usr/local/bin/neko-greet && "
        f'if neko-pkg install {demo}; then false; else true; fi && '
        'test "$(cat /usr/local/bin/neko-greet)" = personal && '
        'rm /usr/local/bin/neko-greet && '
        f'neko-pkg install {demo} && neko-pkg verify neko-greet && '
        'mv /usr/local/lib/neko-pkg/store/neko-greet@0.1.0 '
        '/usr/local/lib/neko-pkg/store/neko-greet && '
        'rm /usr/local/bin/neko-greet && '
        'ln -s /usr/local/lib/neko-pkg/store/neko-greet/payload '
        '/usr/local/bin/neko-greet && neko-pkg verify neko-greet && '
        "test \"$(neko-greet)\" = 'Hello from a NekoOS package' && "
        "neko-pkg list | grep -Fqx 'neko-greet 0.1.0' && "
        "printf '\\n%s%s\\n' 'PACKAGE_' 'INSTALLED' && poweroff || poweroff\n"
    ).encode('ascii')
    dependencies = (
        'neko-pkg verify neko-greet && '
        "test \"$(neko-greet)\" = 'Hello from a NekoOS package' && "
        f'neko-pkg info {companion} | grep -Fqx "depends=neko-greet>=0.2.0" && '
        f'if neko-pkg install {companion}; then false; else true; fi && '
        f'neko-pkg upgrade {newer} && neko-pkg verify neko-greet && '
        "test \"$(neko-greet)\" = 'Hello from NekoOS package v2' && "
        f'if neko-pkg upgrade {newer}; then false; else true; fi && '
        f'if neko-pkg upgrade {demo}; then false; else true; fi && '
        'cp /usr/local/lib/neko-pkg/store/neko-greet@0.2.0/payload /tmp/provider-backup && '
        'printf X >> /usr/local/lib/neko-pkg/store/neko-greet@0.2.0/payload && '
        f'if neko-pkg install {companion}; then false; else true; fi && '
        'cp /tmp/provider-backup /usr/local/lib/neko-pkg/store/neko-greet@0.2.0/payload && '
        f'neko-pkg install {companion} && neko-pkg verify neko-companion && '
        "neko-companion | grep -Fqx 'Companion is ready' && "
        "neko-pkg list | grep -Fqx 'neko-greet 0.2.0' && "
        "neko-pkg list | grep -Fqx 'neko-companion 1.0.0' && "
        "printf '\\n%s%s\\n' 'PACKAGE_' 'DEPENDENCY' && poweroff || poweroff\n"
    ).encode('ascii')
    upgrade_remove = (
        'neko-pkg verify neko-greet && neko-pkg verify neko-companion && '
        'if neko-pkg remove neko-greet; then false; else true; fi && '
        f'neko-pkg upgrade {newest} && '
        "test \"$(neko-greet)\" = 'Hello from NekoOS package v3' && "
        "neko-companion | grep -Fqx 'Companion is ready' && "
        'cp /usr/local/lib/neko-pkg/store/neko-greet@0.3.0/payload /tmp/package-backup && '
        'printf X >> /usr/local/lib/neko-pkg/store/neko-greet@0.3.0/payload && '
        'if neko-pkg verify neko-greet; then false; else true; fi && '
        'cp /tmp/package-backup /usr/local/lib/neko-pkg/store/neko-greet@0.3.0/payload && '
        'neko-pkg verify neko-greet && '
        'neko-pkg remove neko-companion && neko-pkg remove neko-greet && '
        'test ! -e /usr/local/bin/neko-greet && '
        'test -z "$(neko-pkg list)" && '
        'mkdir /usr/local/lib/neko-pkg/store/.stage-interrupted && '
        'mkdir /usr/local/lib/neko-pkg/store/orphan-pkg && '
        "printf '\\n%s%s\\n' 'PACKAGE_' 'UPGRADED' && poweroff || poweroff\n"
    ).encode('ascii')
    clean = (
        'test ! -e /usr/local/bin/neko-greet && '
        'test -z "$(neko-pkg list)" && '
        'test ! -e /usr/local/lib/neko-pkg/store/.stage-interrupted && '
        'test ! -e /usr/local/lib/neko-pkg/store/orphan-pkg && '
        "printf '\\n%s%s\\n' 'PACKAGE_' 'CLEAN' && poweroff || poweroff\n"
    ).encode('ascii')
    with tempfile.TemporaryDirectory(prefix='package-test-', dir=ROOT / 'build') as directory:
        disk = Path(directory) / 'state.img'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(disk), '128M'], check=True)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(disk)], check=True)
        for number, command, marker in ((1, install, 'PACKAGE_INSTALLED'),
                                        (2, dependencies, 'PACKAGE_DEPENDENCY'),
                                        (3, upgrade_remove, 'PACKAGE_UPGRADED'),
                                        (4, clean, 'PACKAGE_CLEAN')):
            run_disk_guest(images, disk, command, marker, number, args.timeout,
                           False, log_prefix='package')
    print('PACKAGE_TEST_PASSED: legacy upgrade, dependencies, integrity and cleanup')
    return 0


def boot_services(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)
    local = '/usr/local/etc/neko/services'
    create = (
        "neko-service list --all | grep -Fqx 'network enabled builtin' && "
        f"printf '%s\\n' '#!/bin/sh' 'case \"$1\" in' "
        "'start) echo demo-ok > /var/lib/neko-services/demo-runs ;;' "
        "'status) echo demo: ready ;;' 'stop) : ;;' '*) exit 2 ;;' "
        f"'esac' > {local}/demo && chmod +x {local}/demo && "
        "neko-service list --all | grep -Fqx 'demo disabled local' && "
        "neko-service enable demo && neko-service disable network && "
        "if neko-service is-enabled network; then false; else true; fi && "
        "neko-service is-enabled demo | grep -Fqx enabled && "
        "printf '\\n%s%s\\n' 'SERVICES_' 'CREATED' && poweroff || poweroff\n"
    ).encode('ascii')
    verify = (
        "test \"$(cat /var/lib/neko-services/demo-runs)\" = demo-ok && "
        "neko-service list --all | grep -Fqx 'network disabled builtin' && "
        "neko-service list --all | grep -Fqx 'demo enabled local' && "
        "ping -c 1 -W 2 127.0.0.1 >/tmp/loopback.log && "
        f"printf '%s\\n' '#!/bin/sh' 'case \"$1\" in' "
        "'start) exit 1 ;;' 'status) echo broken: failed ;;' "
        "'stop) : ;;' '*) exit 2 ;;' 'esac' "
        f"> {local}/broken && chmod +x {local}/broken && "
        "neko-service enable broken && neko-service disable demo && "
        "neko-service enable network && "
        "rm /var/lib/neko-services/demo-runs && "
        "printf '\\n%s%s\\n' 'SERVICES_' 'PERSISTED' && poweroff || poweroff\n"
    ).encode('ascii')
    recover = (
        "test ! -e /var/lib/neko-services/demo-runs && "
        "neko-service list --all | grep -Fqx 'network enabled builtin' && "
        "neko-service list --all | grep -Fqx 'demo disabled local' && "
        "neko-service status broken | grep -Fqx 'broken: last boot start failed' && "
        f"rm {local}/broken && neko-service disable broken && "
        "test ! -e /var/lib/neko-services/enabled/broken && "
        "printf '\\n%s%s\\n' 'SERVICES_' 'RECOVERED' && poweroff || poweroff\n"
    ).encode('ascii')
    with tempfile.TemporaryDirectory(prefix='services-test-', dir=ROOT / 'build') as directory:
        disk = Path(directory) / 'state.img'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(disk), '128M'], check=True)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(disk)], check=True)
        for number, command, marker in ((1, create, 'SERVICES_CREATED'),
                                        (2, verify, 'SERVICES_PERSISTED'),
                                        (3, recover, 'SERVICES_RECOVERED')):
            run_disk_guest(images, disk, command, marker, number, args.timeout,
                           False, log_prefix='services', network=True)
            log = (ROOT / 'build/logs' / f'services-test-{number}.log').read_text(
                errors='replace')
            if number == 2 and ('Starting service: demo' not in log
                                or 'Starting service: network' in log
                                or 'NETWORK_READY' in log):
                raise RuntimeError('Disabled network or enabled local service boot check failed')
            if number == 3 and ('SERVICE_FAILED:broken' not in log
                                or 'Starting service: demo' in log
                                or 'NETWORK_READY' not in log):
                raise RuntimeError('Service failure recovery or re-enabled network failed')
    print('SERVICES_TEST_PASSED: persistent enablement, loopback, and failure recovery')
    return 0


def boot_system(args):
    if not args.no_build:
        subprocess.run(['bash', str(ROOT / 'scripts/build.sh')], check=True)
    images = ROOT / 'out/images'
    subprocess.run(['sha256sum', '-c', 'SHA256SUMS'], cwd=images, check=True)
    subprocess.run([sys.executable, str(ROOT / 'tools/validate_image.py'),
                    str(images / 'initramfs.cpio.gz')], check=True)
    if args.iso:
        if not args.no_build:
            subprocess.run(['bash', str(ROOT / 'scripts/create-iso.sh'), '--system'],
                           check=True)
        subprocess.run(['sha256sum', '-c', 'SYSTEM_ISO_SHA256SUMS'],
                       cwd=images, check=True)
    first = (
        "grep -q ' / ext4 ' /proc/mounts && "
        "test -b /dev/vda && test -b /dev/vdb && "
        "test -x /usr/bin/cc && "
        "printf system-disk > /etc/neko/system-disk-test && "
        "printf state-disk > /root/system-state-test && "
        "sync && printf '\\n%s%s\\n' 'SYSTEM_' 'WRITTEN' && poweroff || poweroff\n"
    ).encode('ascii')
    second = (
        "test \"$(cat /etc/neko/system-disk-test)\" = system-disk && "
        "test \"$(cat /root/system-state-test)\" = state-disk && "
        "cc /usr/share/nekoos/examples/hello.c -o /root/system-hello && "
        "/root/system-hello | grep -Fqx 'Hello from NekoOS' && "
        "rm /etc/neko/system-disk-test /root/system-state-test /root/system-hello && "
        "sync && printf '\\n%s%s\\n' 'SYSTEM_' 'PERSISTED' && poweroff || poweroff\n"
    ).encode('ascii')
    with tempfile.TemporaryDirectory(prefix='system-test-', dir=ROOT / 'build') as directory:
        system_disk = Path(directory) / 'system.img'
        state_disk = Path(directory) / 'state.img'
        subprocess.run(['cp', '--sparse=always', str(images / 'system-template.img'),
                        str(system_disk)], check=True)
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state_disk), '128M'], check=True)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(state_disk)], check=True)
        for number, command, marker in ((1, first, 'SYSTEM_WRITTEN'),
                                        (2, second, 'SYSTEM_PERSISTED')):
            run_disk_guest(images, state_disk, command, marker, number, args.timeout,
                           args.iso, log_prefix='iso-system' if args.iso else 'system',
                           network=True,
                           system_disk=system_disk)
            prefix = 'iso-system' if args.iso else 'system'
            log = (ROOT / 'build/logs' / f'{prefix}-test-{number}.log').read_text(
                errors='replace')
            if 'NETWORK_READY' not in log:
                raise RuntimeError('Network did not start from the system disk')
            if args.iso and 'NEKO_BOOTLOADER_SYSTEM_READY' not in log:
                raise RuntimeError('GRUB did not select the system disk entry')
    print(('ISO_SYSTEM_TEST_PASSED' if args.iso else 'SYSTEM_TEST_PASSED')
          + ': disk root and both filesystems survived poweroff')
    return 0


def run_disk_guest(images, disk, guest_command, marker, pass_number, timeout, iso,
                   log_prefix=None, network=False, system_disk=None):
    prefix = log_prefix or ('iso' if iso else 'disk')
    log = ROOT / 'build/logs' / f'{prefix}-test-{pass_number}.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    command = [
        'qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg',
        '-cpu', 'qemu64', '-m', '256M', '-smp', '2', '-nodefaults',
        '-display', 'none', '-monitor', 'none', '-serial', 'stdio',
        '-nic', ('user,model=virtio-net-pci,ipv6=off' if network else 'none'),
        '-no-reboot',
    ]
    if system_disk is not None:
        command += ['-drive', f'file={system_disk},format=raw,if=virtio']
    command += ['-drive', f'file={disk},format=raw,if=virtio']
    if iso:
        iso_name = 'NekoOS-system.iso' if system_disk is not None else 'NekoOS.iso'
        command += ['-drive', f'file={images / iso_name},media=cdrom,if=ide',
                    '-boot', 'order=d']
        hardware_check = (b'neko-boot-status && '
                          b'test "$(cat /sys/devices/system/cpu/online)" = 0-1 && ')
        guest_command = hardware_check + guest_command.rstrip(b'\n') + b' || poweroff\n'
    else:
        command += ['-kernel', str(images / 'bzImage'),
                    '-initrd', str(images / ('bootstrap.cpio.gz' if system_disk
                                             else 'initramfs.cpio.gz')),
                    '-append', 'console=ttyS0,115200 rdinit=/init panic=-1 '
                               'neko.state=required' +
                               (' neko.system=required' if system_disk else '')]
    with log.open('wb') as output:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output,
                                   stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + timeout
            sent = False
            while time.monotonic() < deadline:
                content = log.read_text(errors='replace')
                lines = content.replace('\r', '').splitlines()
                if ('PERSISTENCE_READY' in lines and 'SYSTEM_READY' in lines
                        and 'built-in shell (ash)' in content and not sent):
                    process.stdin.write(guest_command)
                    process.stdin.flush()
                    sent = True
                code = process.poll()
                if code is not None:
                    lines = log.read_text(errors='replace').replace('\r', '').splitlines()
                    if (code == 0 and sent and marker in lines
                            and (system_disk is None or 'SYSTEM_DISK_READY' in lines)
                            and (not iso or ('NEKO_BOOTLOADER_READY' in content
                                             and 'HARDWARE_READY' in lines))
                            and any('Power down' in line for line in lines)):
                        return
                    raise RuntimeError(f'Disk boot {pass_number} failed; see {log}')
                if 'Kernel panic' in content or 'BOOT_FAILED:' in content:
                    raise RuntimeError(f'Disk boot {pass_number} failed; see {log}')
                time.sleep(0.1)
            raise RuntimeError(f'Disk boot {pass_number} timed out; see {log}')
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
        print(f'See {ROOT / "build/logs"} for the guest boot log', file=sys.stderr)
        sys.exit(1)
