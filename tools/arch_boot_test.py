#!/usr/bin/env python3
"""Fault injection for the first-boot guard, using disposable VM generations."""
import argparse
import hashlib
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

import arch_update as update
vm = update.vm
ROOT = update.ROOT
NOTE_FILE = '/home/neko/Documents/boot-recovery-check.txt'
NEW_FILE = '/home/neko/after-recovery/README.txt'


def interrupted_worker(directory):
    # This entry point is solely a test worker, never a production VM launcher.
    directory = Path(directory).absolute()
    if directory.parent != ROOT / 'build/arch-boot-test' or not directory.name.startswith('qa-'):
        raise RuntimeError('Worker requires a generated QA directory')
    vm.safe_directory(directory)
    original_command, original_enter = vm.qemu_command, vm.Guest.__enter__

    def paused_command(*args, **kwargs):
        return original_command(*args, **kwargs) + ['-S']

    def record_enter(guest):
        result = original_enter(guest)
        update.atomic_json(directory / 'worker-qemu.json', {'pid': guest.process.pid})
        return result

    vm.qemu_command = paused_command
    vm.Guest.__enter__ = record_enter
    with vm.file_lock(directory / '.worker.lock'):
        manager = update.Manager(ROOT, directory)
        with manager.guarded_boot(tag='interrupted-worker', timeout=120):
            raise RuntimeError('Paused guest must never confirm its desktop')


def stage_fixture(manager, fault=None):
    """Simulate a regression discovered after staging; not a release builder."""
    state = manager.load()
    manager.ensure_confirmed(state)
    if state['previous'] is not None:
        manager.forget_previous()  # Explicit removal of this QA-owned failure.
        state = manager.load()
    identifier = 'gen-' + update.uuid.uuid4().hex
    update.clone(manager.disk(state['active']), manager.disk(identifier))
    facts = state['generations'][state['active']]['facts']
    if fault is not None:
        with tempfile.TemporaryDirectory(prefix='inject-home-', dir=manager.directory) as name:
            home = Path(name) / 'home.qcow2'
            update.clone(manager.home, home, 'raw')
            with manager.boot(manager.disk(identifier), home, 'inject-' + fault, home_format='qcow2') as guest:
                if fault == 'kernel':
                    action = 'mv /boot/vmlinuz-linux /boot/vmlinuz-linux.qa-disabled'
                elif fault == 'desktop':
                    action = 'systemctl mask lightdm.service'
                else:
                    raise RuntimeError('Unknown test fault')
                guest.check("printf 'neko\\n' | sudo -S -p '' " + action, 'NEKO_BOOT_FAULT_INJECTED')
                guest.poweroff()
    release = manager.release()
    state['generations'][identifier] = {'snapshot': release['snapshot'], 'facts': facts,
                                       'seal': vm.sha256_file(manager.disk(identifier))}
    state['pending'] = {'id': identifier, 'phase': 'ready', 'release': release}
    manager.save(state)
    manager.activate()
    return identifier, state['active']


def terminate_owned_qemu(pid, directory):
    if not isinstance(pid, int) or pid <= 1:
        raise RuntimeError('Invalid worker PID')
    process = Path('/proc') / str(pid)
    try:
        command = (process / 'cmdline').read_bytes()
    except FileNotFoundError:
        return
    if not command:
        return  # An exited zombie has no command line and owns no image locks.
    if process.stat().st_uid != os.getuid() or str(directory).encode() not in command or b'qemu-system-x86_64' not in command:
        raise RuntimeError('Refusing to stop a process outside this QA VM')
    os.kill(pid, signal.SIGTERM)


def interrupt_first_boot(manager):
    record = manager.directory / 'worker-qemu.json'
    log = manager.logs / 'arch-boot-worker.log'
    with vm.open_guarded_log(log) as output:
        worker = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), 'worker', str(manager.directory)],
                                  stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT)
        pid = None
        try:
            deadline = time.monotonic() + 120
            while not record.exists() or not list(manager.directory.glob('managed-boot-*/qmp.sock')):
                if worker.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError(f'No interrupted worker QEMU; see {log}')
                time.sleep(.1)
            pid = update.json.loads(vm.read_regular(record))['pid']
            if manager.load(check_disks=False)['trial']['phase'] != 'booting':
                raise RuntimeError('Worker did not persist its unconfirmed boot')
            worker.kill()  # Actual SIGKILL: no Python finally/metadata cleanup.
            worker.wait(timeout=10)
            before = manager.state_path.read_bytes()
            try:
                with manager.guarded_boot(tag='must-refuse-orphan'):
                    raise RuntimeError('An orphan writer was incorrectly accepted')
            except subprocess.CalledProcessError:
                pass  # qemu-img refuses QEMU's write lock; no state was changed.
            else:
                raise RuntimeError('An orphan writer was not detected')
            if manager.state_path.read_bytes() != before:
                raise RuntimeError('Recovery changed state while the orphan was still writing')
            terminate_owned_qemu(pid, manager.directory)
            deadline = time.monotonic() + 15
            active = manager.load(check_disks=False)['active']
            while True:
                try:
                    update.standalone(manager.disk(active))
                    break
                except subprocess.CalledProcessError:
                    if time.monotonic() > deadline:
                        raise RuntimeError('QA orphan did not release its disk')
                    time.sleep(.1)
        finally:
            if worker.poll() is None:
                worker.kill(); worker.wait(timeout=10)
            if pid is not None:
                terminate_owned_qemu(pid, manager.directory)


def test_boot_guard(root=ROOT):
    inputs = {name: vm.sha256_file(root / name) for name in ('tools/arch_update.py', 'tools/arch_boot_test.py')}
    summary_path = root / 'build/logs/arch-boot-test-summary.json'
    update.atomic_json(summary_path, {'result': 'running'})
    parent = vm.safe_directory(root / 'build/arch-boot-test', create=True)
    digest = hashlib.sha256(update.NOTE.encode()).hexdigest()
    check = f'test -O {NOTE_FILE}; test "$(sha256sum {NOTE_FILE} | cut -d\" \" -f1)" = {digest}\n'
    after_check = f'test -O {NEW_FILE}; test "$(sha256sum {NEW_FILE} | cut -d\" \" -f1)" = {digest}\n'
    source = root / 'out/arch/managed'
    source_hashes = {str(path.relative_to(root)): vm.sha256_file(path) for path in
                     [source / 'state.json', source / 'home.img', *sorted(source.glob('gen-*.qcow2'))] if path.exists()}
    with tempfile.TemporaryDirectory(prefix='qa-', dir=parent) as name:
        manager = update.Manager(root, Path(name))
        manager.initialize(vm.verify_images(root))
        old = manager.load()['active']
        manager.health(old, manager.home, 'guard-data', extra=
                       f'printf %s {update.shlex.quote(update.NOTE)} > {NOTE_FILE}\n' + check)
        results = {}
        for fault, uefi in (('kernel', False), ('desktop', True)):
            candidate, previous = stage_fixture(manager, fault)
            with manager.guarded_boot(tag='guard-' + fault, uefi=uefi, timeout=50) as guest:
                guest.check(check, 'NEKO_RECOVERY_DATA_READY')
                if fault == 'desktop':
                    guest.qmp.key('ctrl-shift-n'); time.sleep(.7)
                    guest.qmp.type_ascii('after-recovery'); guest.qmp.key('ret')
                    guest.check('attempt=0\nwhile ! test -d "$HOME/after-recovery"; do\n'
                                'attempt=$((attempt+1)); test "$attempt" -lt 30; sleep 1\ndone\n'
                                f'printf %s {update.shlex.quote(update.NOTE)} > {NEW_FILE}\n' + after_check,
                                'NEKO_RECOVERED_GUI_INPUT_READY')
                    guest.qmp.screenshot(manager.previews / 'arch-boot-recovery.png')
                guest.poweroff()
            state = manager.load()
            if (state['active'] != previous or state['previous'] != candidate or state['trial'] is not None or
                    state['last_recovery']['cause'] != 'desktop_not_ready'):
                raise RuntimeError('Failed boot was not automatically recovered')
            results[fault + '_automatic_recovery'] = True
        candidate, previous = stage_fixture(manager)
        interrupt_first_boot(manager)
        with manager.guarded_boot(tag='guard-interrupted', uefi=True, timeout=90, offline=True) as guest:
            guest.check(check + after_check, 'NEKO_INTERRUPTED_RECOVERY_DATA_READY')
            guest.poweroff()
        state = manager.load()
        if state['active'] != previous or state['last_recovery']['cause'] != 'interrupted_boot':
            raise RuntimeError('Interrupted management process was not recovered')
        # A good, offline first boot must confirm and must not roll back again.
        candidate, previous = stage_fixture(manager)
        with manager.guarded_boot(tag='guard-success', timeout=90, offline=True) as guest:
            guest.check(check + after_check, 'NEKO_OFFLINE_FIRST_BOOT_READY')
            guest.poweroff()
        state = manager.load()
        if state['active'] != candidate or state['previous'] != previous or state['trial'] is not None:
            raise RuntimeError('Healthy offline first boot did not confirm')
        results.update(interrupted_manager_recovered=True, orphan_writer_refused=True,
                       offline_success_confirmed=True, recovery_gui_input=True,
                       user_file_sha256=digest, validation_inputs_sha256=inputs)
    if inputs != {name: vm.sha256_file(root / name) for name in inputs}:
        raise RuntimeError('Boot-guard sources changed during QA')
    if source_hashes != {name: vm.sha256_file(root / name) for name in source_hashes}:
        raise RuntimeError('QA modified the actual managed VM')
    update.atomic_json(summary_path, {'result': 'passed', **results, 'actual_managed_vm_unchanged': True})
    print('NEKO_BOOT_GUARD_TEST_PASSED', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('worker',))
    parser.add_argument('directory')
    args = parser.parse_args()
    interrupted_worker(args.directory)
