#!/usr/bin/env python3
"""Transactional updates for an opt-in VM, with a separate persistent home."""
import argparse
import base64
from contextlib import contextmanager
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arch_vm as vm

ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r'gen-[0-9a-f]{32}')
SHA = re.compile(r'[0-9a-f]{64}')
NOTE = 'NekoOS: данные отдельно от версии системы.\n'
HOME_FILE = '/home/neko/Documents/Neko-update-check.txt'
AFTER_FILE = '/home/neko/after-update/README.txt'


class BootFailure(RuntimeError):
    """The guest started but failed to reach a working desktop."""


class BootCancelled(RuntimeError):
    """A user closed an unconfirmed VM; allow another attempt."""


BOOT_CHECK = r'''
test "$(id -u)" = 1000
test "$(cat /proc/1/comm)" = systemd
test "$(uname -r)" = "$(pacman -Qlq linux | sed -n 's@^/usr/lib/modules/\([^/]*\)/pkgbase$@\1@p')"
test "$(systemctl is-enabled lightdm.service)" != masked
attempt=0
until systemctl is-active --quiet lightdm.service &&
      pgrep -u 1000 -x xfce4-session >/dev/null &&
      pgrep -u 1000 -x xfce4-panel >/dev/null &&
      pgrep -u 1000 -x xfdesktop >/dev/null &&
      pgrep -u 1000 -x xfwm4 >/dev/null &&
      pgrep -u 1000 -x '[Tt]hunar' >/dev/null; do
    if systemctl is-failed --quiet lightdm.service; then exit 1; fi
    attempt=$((attempt + 1)); test "$attempt" -lt 90; sleep 1
done
desktop_environment
read -r screen_width screen_height < <(xdotool getdisplaygeometry)
attempt=0
until mapped_shell_window '[Xx]fce4-panel' DOCK "$((screen_width / 2))" 16 &&
      mapped_shell_window '[Xx]fdesktop' DESKTOP "$((screen_width * 9 / 10))" "$((screen_height * 9 / 10))"; do
    attempt=$((attempt + 1)); test "$attempt" -lt 90; sleep 1
done
attempt=0
until wmctrl -xa Thunar; do
    attempt=$((attempt + 1)); test "$attempt" -lt 30; sleep 1
done
'''


def release_record(value):
    if (not isinstance(value, dict) or set(value) != {'format', 'channel', 'snapshot', 'architecture', 'databases'}
            or value['format'] != 1 or value['channel'] != 'testing' or value['architecture'] != 'x86_64'
            or not isinstance(value['snapshot'], str) or not re.fullmatch(r'\d{4}/\d{2}/\d{2}', value['snapshot'])
            or not isinstance(value['databases'], dict) or set(value['databases']) != {'core', 'extra'}
            or any(not isinstance(x, str) or SHA.fullmatch(x) is None for x in value['databases'].values())):
        raise RuntimeError('Invalid pinned testing release')
    datetime.datetime.strptime(value['snapshot'], '%Y/%m/%d')
    return value


def atomic_json(path, value):
    vm.safe_directory(path.parent, create=True)
    if os.path.lexists(path):
        vm.safe_regular(path, writable=True)
    descriptor, name = tempfile.mkstemp(prefix='.state-', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        temporary.unlink(missing_ok=True)


def standalone(path):
    info = vm.qcow_info(path)
    data = info.get('format-specific', {}).get('data', {})
    if (info.get('format') != 'qcow2' or info.get('backing-filename') or info.get('full-backing-filename')
            or info.get('data-file') or data.get('data-file') or data.get('corrupt')):
        raise RuntimeError(f'Unexpected external backing/data or corrupt managed disk: {path}')
    return info


def clone(source, destination, source_format='qcow2'):
    if os.path.lexists(destination):
        raise RuntimeError('Refusing to overwrite a generation')
    vm.safe_regular(source)
    vm.safe_directory(destination.parent)
    subprocess.run(['qemu-img', 'convert', '-f', source_format, '-O', 'qcow2', str(source), str(destination)], check=True)
    destination.chmod(0o600)
    standalone(destination)


MIGRATE = r'''
printf 'neko\n' | sudo -S -p '' bash -c '
set -euo pipefail
test "$(blkid -s LABEL -o value /dev/vdb)" = NEKO_HOME
test -z "$(findmnt -rn -S /dev/vdb)"
systemctl stop lightdm.service
install -d -m 0700 /mnt/neko-home-import
mount /dev/vdb /mnt/neko-home-import
rsync -aHAX --numeric-ids /home/ /mnt/neko-home-import/
test -z "$(rsync -aHAXnc --numeric-ids --itemize-changes /home/ /mnt/neko-home-import/)"
home_uuid=$(blkid -s UUID -o value /dev/vdb)
printf "UUID=%s /home ext4 defaults 0 2\n" "$home_uuid" >> /etc/fstab
umount /mnt/neko-home-import
mount /home
printf "snapshot=imported\nchannel=local\n" > /usr/share/nekoos/managed-release
pacman -Q > /usr/share/nekoos/managed-packages.lock
'
cd /home/neko
'''

HOME_CHECK = r'''
test "$(findmnt -n -o TARGET /home)" = /home
test "$(findmnt -n -o FSTYPE /home)" = ext4
test "$(findmnt -n -o SOURCE /home)" = /dev/vdb
test -O "$HOME"; test -w "$HOME"
'''


class Manager:
    def __init__(self, root=ROOT, directory=None, timeout=1200):
        self.root = Path(root)
        self.directory = vm.safe_directory(directory or self.root / 'out/arch/managed', create=True)
        self.state_path = self.directory / 'state.json'
        self.home = self.directory / 'home.img'
        self.timeout = timeout
        self.logs = vm.safe_directory(self.root / 'build/logs', create=True)
        self.previews = vm.safe_directory(self.root / 'out/previews', create=True)

    def disk(self, identifier):
        if not isinstance(identifier, str) or ID.fullmatch(identifier) is None:
            raise RuntimeError('Unsafe generation identifier')
        return self.directory / f'{identifier}.qcow2'

    def save(self, state):
        atomic_json(self.state_path, state)

    def load(self, check_disks=True):
        state = json.loads(vm.read_regular(self.state_path))
        # Old VM metadata remains readable. Persist migration with the next
        # state transition, never rewrite a user's disks to enable the guard.
        if isinstance(state, dict) and state.get('format') == 1:
            if set(state) != {'format', 'active', 'previous', 'pending', 'generations'}:
                raise RuntimeError('Invalid legacy managed VM state')
            state = {**state, 'format': 2, 'trial': None, 'last_recovery': None}
            if state['previous'] is not None:
                state['trial'] = self.new_trial(state)
        if (not isinstance(state, dict) or set(state) != {'format', 'active', 'previous', 'pending', 'generations'}
                | {'trial', 'last_recovery'} or state['format'] != 2 or not isinstance(state['generations'], dict)):
            raise RuntimeError('Invalid managed VM state')
        for identifier, record in state['generations'].items():
            self.disk(identifier)
            if (not isinstance(record, dict) or set(record) != {'snapshot', 'seal', 'facts'}
                    or not isinstance(record['snapshot'], str)
                    or record['seal'] is not None and (not isinstance(record['seal'], str) or SHA.fullmatch(record['seal']) is None)
                    or not isinstance(record['facts'], dict)):
                raise RuntimeError('Invalid generation metadata')
        pending = state['pending']
        if pending is not None:
            if (not isinstance(pending, dict) or set(pending) != {'id', 'phase', 'release'}
                    or not isinstance(pending['id'], str)
                    or pending['phase'] not in ('preparing', 'failed', 'ready')
                    or pending['id'] not in state['generations']):
                raise RuntimeError('Invalid pending transaction')
            release_record(pending['release'])
            self.disk(pending['id'])
            record = state['generations'][pending['id']]
            if record['snapshot'] != pending['release']['snapshot']:
                raise RuntimeError('Candidate snapshot does not match its transaction')
            if pending['phase'] == 'ready' and (record['seal'] is None or
                    set(record['facts']) != {'KERNEL', 'PACKAGES'} or
                    not isinstance(record['facts']['PACKAGES'], str) or
                    SHA.fullmatch(record['facts']['PACKAGES']) is None):
                raise RuntimeError('Ready candidate lacks its verification seal and release facts')
        references = [state['active']] + ([state['previous']] if state['previous'] is not None else [])
        if pending is not None:
            references.append(pending['id'])
        for identifier in references:
            self.disk(identifier)
        if len(set(references)) != len(references) or set(references) != set(state['generations']):
            raise RuntimeError('Invalid generation references')
        trial = state['trial']
        if trial is not None:
            if (not isinstance(trial, dict) or set(trial) != {'id', 'previous', 'phase', 'nonce'} or
                    trial['id'] != state['active'] or trial['previous'] != state['previous'] or
                    state['previous'] is None or state['pending'] is not None or
                    trial['phase'] not in ('armed', 'booting') or
                    not isinstance(trial['nonce'], str) or not re.fullmatch('[0-9a-f]{32}', trial['nonce'])):
                raise RuntimeError('Invalid first-boot recovery state')
        recovery = state['last_recovery']
        if recovery is not None:
            if (not isinstance(recovery, dict) or set(recovery) != {'failed', 'restored', 'cause', 'time_utc'} or
                    recovery['cause'] not in ('desktop_not_ready', 'interrupted_boot') or
                    not isinstance(recovery['time_utc'], str) or
                    not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', recovery['time_utc'])):
                raise RuntimeError('Invalid recovery history')
            self.disk(recovery['failed']); self.disk(recovery['restored'])
        vm.safe_regular(self.home, writable=True)
        for identifier in references:
            if pending is not None and identifier == pending['id'] and pending['phase'] != 'ready':
                continue  # An interrupted copy is discardable; it is never bootable.
            record = state['generations'][identifier]
            if (set(record['facts']) != {'KERNEL', 'PACKAGES'} or
                    not isinstance(record['facts']['KERNEL'], str) or not record['facts']['KERNEL'] or
                    not isinstance(record['facts']['PACKAGES'], str) or
                    SHA.fullmatch(record['facts']['PACKAGES']) is None):
                raise RuntimeError('Bootable generation lacks its package/kernel verification facts')
            if identifier != state['active'] and record['seal'] is None:
                raise RuntimeError('Inactive generation is missing its verification seal')
            if check_disks:
                standalone(self.disk(identifier))
            if check_disks and identifier != state['active'] and state['generations'][identifier]['seal'] is not None:
                if vm.sha256_file(self.disk(identifier)) != state['generations'][identifier]['seal']:
                    raise RuntimeError('Inactive generation checksum failed; preserving all disks')
        return state

    def new_trial(self, state):
        return {'id': state['active'], 'previous': state['previous'],
                'phase': 'armed', 'nonce': uuid.uuid4().hex}

    def ensure_confirmed(self, state):
        if state['trial'] is not None:
            raise RuntimeError('First boot is not confirmed. Run or verify the VM before preparing or deleting recovery generations')

    def begin_boot(self, state):
        if state['trial'] is None or state['trial']['phase'] != 'armed':
            raise RuntimeError('No armed first boot')
        state['trial']['phase'] = 'booting'
        state['trial']['nonce'] = uuid.uuid4().hex
        self.save(state)  # Durable before QEMU starts; power loss cannot count as success.
        return state['trial']['nonce']

    def finish_boot(self, identifier, nonce, cancelled=False):
        # QEMU owns the disk locks now. Validate metadata without opening
        # those disks; the launcher holds the managed lock for this entire run.
        state = self.load(check_disks=False)
        trial = state['trial']
        if trial is None or (trial['id'], trial['nonce'], trial['phase']) != (identifier, nonce, 'booting'):
            raise RuntimeError('Stale or mismatched first-boot confirmation')
        state['trial'] = self.new_trial(state) if cancelled else None
        self.save(state)

    def recover_boot(self, cause):
        state = self.load()  # Refuses an orphan QEMU writer or altered fallback.
        if state['trial'] is None or state['trial']['phase'] != 'booting':
            raise RuntimeError('No interrupted or failed first boot to recover')
        if cause not in ('desktop_not_ready', 'interrupted_boot'):
            raise RuntimeError('Invalid recovery cause')
        failed, restored = state['active'], state['previous']
        state['generations'][failed]['seal'] = vm.sha256_file(self.disk(failed))
        state['active'], state['previous'] = restored, failed
        state['trial'] = None  # Never loop between two broken generations.
        state['last_recovery'] = {'failed': failed, 'restored': restored, 'cause': cause,
                                 'time_utc': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
        self.save(state)
        print('Новая версия не подтвердила рабочий стол. Возвращаю предыдущую систему; домашний диск сохраняется.', flush=True)
        return state

    def require_space(self):
        # Accommodate a fully allocated 12 GiB root + 8 GiB private home, with margin.
        if shutil.disk_usage(self.directory).free < 24 * 1024**3:
            raise RuntimeError('At least 24 GiB of host space is required before staging')

    def release(self):
        return release_record(json.loads(vm.read_regular(self.root / 'arch/releases/testing.json')))

    @contextmanager
    def boot(self, disk, home, tag, uefi=False, offline=False, home_format='raw',
             headless=True, no_reboot=True, guarded=False, timeout=None):
        with tempfile.TemporaryDirectory(prefix='managed-boot-', dir=self.directory) as name:
            work = Path(name)
            qmp = work / 'qmp.sock'
            firmware = vm.uefi_firmware(work) if uefi else None
            command = vm.qemu_command(disk, 'grub', headless=headless, qmp_path=qmp, firmware=firmware, no_reboot=no_reboot)
            command += ['-drive', f'file={str(home).replace(",", ",,")},format={home_format},if=virtio']
            if offline:
                index = command.index('-nic')
                command[index + 1] = 'none'
            log = self.logs / f'arch-update-{tag}.log'
            with vm.Guest(command, log, timeout=timeout or self.timeout) as guest:
                while not qmp.exists():
                    if guest.process.poll() is not None or time.monotonic() >= guest.deadline:
                        raise RuntimeError(f'No update QMP socket; see {log}')
                    time.sleep(.1)
                guest.qmp = vm.QMP(qmp)
                try:
                    guest.wait('NEKO_ARCH_READY')
                except RuntimeError as error:
                    if guarded:
                        self.raise_boot_error(guest, error)
                    raise
                guest.send('stty -echo; set +o history; cd /home/neko')
                yield guest

    def raise_boot_error(self, guest, error):
        if 'Kernel panic' in guest.content() or guest.process.poll() is None:
            if guest.qmp is not None:
                try:
                    guest.qmp.screenshot(self.previews / (guest.log.stem + '-failed.png'))
                except (OSError, RuntimeError):
                    pass
            raise BootFailure(str(error)) from error
        if guest.process.returncode == 0:
            raise BootCancelled('First boot was closed before confirmation') from error
        raise error  # Host/display/storage startup failures do not select another OS.

    @contextmanager
    def guarded_boot(self, tag='first-boot', headless=True, uefi=False, timeout=180, offline=False):
        state = self.load()
        if state['trial'] is not None and state['trial']['phase'] == 'booting':
            state = self.recover_boot('interrupted_boot')
        identifier = state['active']
        nonce = self.begin_boot(state) if state['trial'] is not None else None
        confirmed = False
        try:
            with self.boot(self.disk(identifier), self.home, tag, uefi, offline,
                           headless=headless, no_reboot=False, guarded=nonce is not None, timeout=timeout) as guest:
                if nonce is not None:
                    try:
                        guest.check(HOME_CHECK + BOOT_CHECK, 'NEKO_BOOT_READY_' + nonce)
                    except RuntimeError as error:
                        self.raise_boot_error(guest, error)
                    self.finish_boot(identifier, nonce)
                    print('Рабочий стол новой версии проверен. Предыдущая система сохранена для отката.', flush=True)
                else:
                    guest.check(HOME_CHECK + BOOT_CHECK, 'NEKO_RECOVERED_DESKTOP_READY')
                confirmed = True
                yield guest
        except BootFailure:
            if confirmed or nonce is None:
                raise
            # The Guest context has stopped QEMU before changing pointers or hashes.
            recovered = self.recover_boot('desktop_not_ready')
            with self.boot(self.disk(recovered['active']), self.home, tag + '-recovered', uefi, offline,
                           headless=headless, no_reboot=False, timeout=timeout) as guest:
                guest.check(HOME_CHECK + BOOT_CHECK, 'NEKO_RECOVERED_DESKTOP_READY')
                yield guest  # One fallback attempt; an unhealthy fallback stops here.
        except BaseException:
            if nonce is not None and not confirmed:
                current = self.load(check_disks=False)['trial']
                if current is not None and (current['id'], current['nonce'], current['phase']) == (identifier, nonce, 'booting'):
                    self.finish_boot(identifier, nonce, cancelled=True)
            raise

    def install_helper(self, guest):
        source = self.root / 'arch/airootfs/usr/local/bin/neko-update'
        payload = vm.read_regular(source)
        encoded = base64.b64encode(payload).decode()
        guest.check("printf 'neko\\n' | sudo -S -p '' install -m 0600 /dev/null /run/neko-update.b64", 'NEKO_HELPER_BEGIN')
        for index, offset in enumerate(range(0, len(encoded), 1600)):
            chunk = encoded[offset:offset + 1600]
            guest.check(f"printf %s {shlex.quote(chunk)} | sudo -n tee -a /run/neko-update.b64 >/dev/null",
                        f'NEKO_HELPER_CHUNK_{index}')
        digest = hashlib.sha256(payload).hexdigest()
        guest.check("sudo -n bash -c 'base64 -d /run/neko-update.b64 > /usr/local/bin/neko-update; "
                    "chmod 0755 /usr/local/bin/neko-update; rm /run/neko-update.b64'\n"
                    f'test "$(sha256sum /usr/local/bin/neko-update | cut -d\" \" -f1)" = {digest}', 'NEKO_HELPER_READY')

    def facts(self, guest):
        guest.check('printf "NEKO_FACT_KERNEL=%s\\n" "$(uname -r)"\n'
                    'printf "NEKO_FACT_PACKAGES=%s\\n" "$(pacman -Q | sha256sum | cut -d\" \" -f1)"', 'NEKO_FACTS_READY')
        facts = dict(re.findall(r'^NEKO_FACT_(KERNEL|PACKAGES)=([^\n]+)$', guest.content(), re.M))
        if set(facts) != {'KERNEL', 'PACKAGES'} or SHA.fullmatch(facts['PACKAGES']) is None:
            raise RuntimeError('Missing guest release facts')
        return facts

    def initialize(self, verified, source=None):
        if os.path.lexists(self.state_path) or os.path.lexists(self.home) or any(self.directory.glob('gen-*.qcow2')):
            raise RuntimeError('Managed VM already exists or initialization was interrupted; preserving it')
        self.require_space()
        identifier = 'gen-' + uuid.uuid4().hex
        root_disk = self.disk(identifier)
        images = verified[0]
        if verified[2] != 'grub':
            raise RuntimeError('Managed updates require the GPT/GRUB image')
        clone(source or images / 'system-template.img', root_disk, 'qcow2' if source else 'raw')
        with self.home.open('xb') as stream:
            stream.truncate(8 * 1024**3)
        self.home.chmod(0o600)
        subprocess.run(['mkfs.ext4', '-q', '-F', '-m', '0', '-L', 'NEKO_HOME', str(self.home)], check=True)
        with self.boot(root_disk, self.home, 'init') as guest:
            guest.check(MIGRATE, 'NEKO_HOME_IMPORTED')
            self.install_helper(guest)
            guest.check(HOME_CHECK, 'NEKO_HOME_READY')
            facts = self.facts(guest)
            guest.poweroff()
        self.health(identifier, self.home, 'init-verify')
        self.save({'format': 2, 'active': identifier, 'previous': None, 'pending': None,
                   'trial': None, 'last_recovery': None,
                   'generations': {identifier: {'snapshot': 'imported', 'seal': None, 'facts': facts}}})
        print('NEKO_MANAGED_INIT_PASSED: copied system, separate home; original VM retained', flush=True)

    def health(self, identifier, home, tag, uefi=False, extra='', home_format='raw'):
        with self.boot(self.disk(identifier), home, tag, uefi, home_format=home_format) as guest:
            kernel_check = r'''test "$(uname -r)" = "$(pacman -Qlq linux | sed -n 's@^/usr/lib/modules/\([^/]*\)/pkgbase$@\1@p')"'''
            guest.check(HOME_CHECK + vm.CORE_CHECK + '\n' + kernel_check + '\n' + extra,
                        'NEKO_MANAGED_HEALTH_READY')
            guest.qmp.screenshot(self.previews / f'arch-update-{tag}.png')
            facts = self.facts(guest)
            guest.poweroff()
        return facts

    def prepare(self, fault=None):
        state = self.load()
        self.ensure_confirmed(state)
        if state['pending'] is not None:
            raise RuntimeError('A candidate already exists; activate it or discard it before preparing another')
        if state['previous'] is not None:
            raise RuntimeError('Previous recovery generation is retained; remove it explicitly with forget-previous before another update')
        release = self.release()
        if state['generations'][state['active']]['snapshot'] == release['snapshot']:
            raise RuntimeError('This snapshot is already active')
        self.require_space()
        identifier = 'gen-' + uuid.uuid4().hex
        state['generations'][identifier] = {'snapshot': release['snapshot'], 'seal': None, 'facts': {}}
        state['pending'] = {'id': identifier, 'phase': 'preparing', 'release': release}
        self.save(state)
        original_root = vm.sha256_file(self.disk(state['active']))
        original_home = vm.sha256_file(self.home)
        try:
            clone(self.disk(state['active']), self.disk(identifier))
            with tempfile.TemporaryDirectory(prefix='candidate-home-', dir=self.directory) as name:
                private_home = Path(name) / 'home.qcow2'
                clone(self.home, private_home, 'raw')
                with self.boot(self.disk(identifier), private_home, 'prepare-' + (fault or 'normal'),
                               offline=fault == 'offline', home_format='qcow2') as guest:
                    guest.check(HOME_CHECK, 'NEKO_STAGE_HOME_READY')
                    self.install_helper(guest)
                    token = uuid.uuid4().hex
                    guest.check(f'printf %s {token} | sudo -n tee /run/neko-update-staging >/dev/null', 'NEKO_STAGING_READY')
                    command = ['sudo', '-n', '/usr/local/bin/neko-update', 'prepare', token, release['snapshot'],
                               release['databases']['core'], release['databases']['extra']]
                    guest.send(shlex.join(command) + ' || ' + vm.marker_command('ARCH_GUEST_FAILED'))
                    if fault == 'interrupt':
                        guest.wait('NEKO_UPDATE_TRANSACTION_ACTIVE')
                        guest.qmp.execute('quit')
                        guest.process.wait(timeout=10)
                        raise RuntimeError('QA interrupted a real ALPM transaction')
                    guest.wait('NEKO_UPDATE_PREPARED')
                    guest.poweroff()
                facts = self.health(identifier, private_home, 'candidate', home_format='qcow2')
                # Second firmware gate uses the same isolated home, never real user data.
                self.health(identifier, private_home, 'candidate-uefi', uefi=True, home_format='qcow2')
            if vm.sha256_file(self.disk(state['active'])) != original_root or vm.sha256_file(self.home) != original_home:
                raise RuntimeError('Staging unexpectedly changed active system or home')
            subprocess.run(['qemu-img', 'check', '-q', '-f', 'qcow2', str(self.disk(identifier))], check=True)
            state['generations'][identifier]['seal'] = vm.sha256_file(self.disk(identifier))
            state['generations'][identifier]['facts'] = facts
            state['pending']['phase'] = 'ready'
            self.save(state)
            print('NEKO_UPDATE_READY: signed full upgrade, BIOS+UEFI desktop tested, active system/home unchanged', flush=True)
        except BaseException:
            state['pending']['phase'] = 'failed'
            self.save(state)
            raise

    def activate(self):
        state = self.load()
        if state['pending'] is None or state['pending']['phase'] != 'ready':
            raise RuntimeError('Only a completely tested candidate may be activated')
        previous = state['active']
        state['generations'][previous]['seal'] = vm.sha256_file(self.disk(previous))
        state['active'] = state['pending']['id']
        state['previous'] = previous
        state['pending'] = None
        state['trial'] = self.new_trial(state)
        self.save(state)  # The single durable switch; both complete roots remain present.
        print('NEKO_UPDATE_ACTIVATED: previous system retained; home was not switched', flush=True)

    def rollback(self):
        state = self.load()
        if state['pending'] is not None or state['previous'] is None:
            raise RuntimeError('Rollback requires a retained generation and no pending transaction')
        state['generations'][state['active']]['seal'] = vm.sha256_file(self.disk(state['active']))
        state['active'], state['previous'] = state['previous'], state['active']
        state['trial'] = self.new_trial(state)
        self.save(state)
        print('NEKO_UPDATE_ROLLED_BACK: previous system selected; current home retained', flush=True)

    def discard(self):
        state = self.load()
        if state['pending'] is None:
            raise RuntimeError('No pending transaction')
        identifier = state['pending']['id']
        path = self.disk(identifier)
        if os.path.lexists(path):
            vm.safe_regular(path, writable=True)
        state['pending'] = None
        del state['generations'][identifier]
        self.save(state)
        path.unlink(missing_ok=True)

    def forget_previous(self):
        state = self.load()
        self.ensure_confirmed(state)
        if state['pending'] is not None or state['previous'] is None:
            raise RuntimeError('A retained generation and no pending transaction are required')
        identifier = state['previous']
        state['previous'] = None
        del state['generations'][identifier]
        self.save(state)
        self.disk(identifier).unlink()

    def run(self, headless=False, uefi=False):
        state = self.load()
        if state['trial'] is not None:
            print('Проверяю первый запуск. Журнал: build/logs/arch-update-first-boot.log', flush=True)
            if headless:
                print('При первом запуске консоль занята проверкой. Для обычной консоли запустите VM повторно после подтверждения.', flush=True)
            with self.guarded_boot(headless=headless, uefi=uefi) as guest:
                guest.process.wait()
            return
        with tempfile.TemporaryDirectory(prefix='managed-run-', dir=self.directory) as name:
            firmware = vm.uefi_firmware(Path(name)) if uefi else None
            command = vm.qemu_command(self.disk(state['active']), 'grub', headless=headless, firmware=firmware)
            command += ['-drive', f'file={str(self.home).replace(",", ",,")},format=raw,if=virtio']
            vm.run_vm(command, headless, self.root)

    def verify(self, uefi=False):
        with self.guarded_boot(tag='verify-boot', uefi=uefi) as guest:
            guest.check(HOME_CHECK + BOOT_CHECK, 'NEKO_VERIFIED_DESKTOP_READY')
            guest.qmp.screenshot(self.previews / 'arch-verified-boot.png')
            guest.poweroff()
        print('NEKO_MANAGED_BOOT_VERIFIED', flush=True)


def test_updates(root=ROOT, timeout=1200):
    inputs = {name: vm.sha256_file(root / name) for name in (
        'tools/arch_update.py', 'arch/airootfs/usr/local/bin/neko-update', 'arch/releases/testing.json')}
    atomic_json(root / 'build/logs/arch-update-test-summary.json', {'result': 'running'})
    verified = vm.verify_images(root)
    work_parent = vm.safe_directory(root / 'build/arch-update', create=True)
    with tempfile.TemporaryDirectory(prefix='qa-', dir=work_parent) as name:
        manager = Manager(root, Path(name), timeout)
        manager.initialize(verified)
        state = manager.load()
        old = state['active']
        digest = hashlib.sha256(NOTE.encode()).hexdigest()
        write = f'printf %s {shlex.quote(NOTE)} > {HOME_FILE}\n'
        check = f'test -O {HOME_FILE}; test "$(sha256sum {HOME_FILE} | cut -d\" \" -f1)" = {digest}\n'
        manager.health(old, manager.home, 'data-before', extra=write + check)
        root_hash, home_hash = vm.sha256_file(manager.disk(old)), vm.sha256_file(manager.home)
        for fault in ('offline', 'interrupt'):
            try:
                manager.prepare(fault=fault)
            except RuntimeError as error:
                if manager.load()['pending']['phase'] != 'failed':
                    raise
                if fault == 'interrupt' and str(error) != 'QA interrupted a real ALPM transaction':
                    raise RuntimeError('The interruption test did not reach an ALPM upgrade') from error
                if fault == 'offline' and 'NEKO_UPDATE_ERROR: No network route;' not in (
                        manager.logs / 'arch-update-prepare-offline.log').read_text(errors='replace'):
                    raise RuntimeError('The offline test did not reach the network precondition') from error
                print(f'Expected failure ({fault}): {error}', flush=True)
            else:
                raise RuntimeError(f'{fault} unexpectedly succeeded')
            if manager.load()['active'] != old or vm.sha256_file(manager.disk(old)) != root_hash or vm.sha256_file(manager.home) != home_hash:
                raise RuntimeError('A failed transaction modified active system or user data')
            manager.discard()
        manager.prepare()
        staged = manager.load()
        candidate = staged['pending']['id']
        if staged['generations'][candidate]['facts']['PACKAGES'] == staged['generations'][old]['facts']['PACKAGES']:
            raise RuntimeError('QA release did not actually update packages')
        manager.activate()
        create_after = r'''desktop_environment
wmctrl -xa Thunar
'''
        with manager.guarded_boot(tag='activated') as guest:
            guest.check(HOME_CHECK + vm.CORE_CHECK + check + create_after, 'NEKO_ACTIVATED_DESKTOP_READY')
            guest.qmp.key('ctrl-shift-n'); time.sleep(.7)
            guest.qmp.type_ascii('after-update'); guest.qmp.key('ret')
            guest.check('attempt=0\nwhile ! test -d "$HOME/after-update"; do\n'
                        'attempt=$((attempt+1)); test "$attempt" -lt 30; sleep 1\ndone\n'
                        f'printf %s {shlex.quote(NOTE)} > {AFTER_FILE}\n', 'NEKO_AFTER_UPDATE_DATA_READY')
            guest.poweroff()
        manager.rollback()
        restored = manager.health(old, manager.home, 'rollback', uefi=True, extra=check +
                                  f'test -O {AFTER_FILE}; test "$(sha256sum {AFTER_FILE} | cut -d\" \" -f1)" = {digest}\n')
        if restored != staged['generations'][old]['facts']:
            raise RuntimeError('Rollback did not restore the original kernel and package versions')
        summary = {'result': 'passed', 'source_packages': staged['generations'][old]['facts'],
                   'updated_packages': staged['generations'][candidate]['facts'],
                   'snapshot': manager.release()['snapshot'], 'offline_preserved_active': True,
                   'interrupted_alpm_preserved_active': True, 'home_survived_update_and_rollback': True,
                   'post_update_gui_file_survived_rollback': True, 'candidate_bios_uefi': True,
                   'unchanged_active_sha256_after_failures': root_hash,
                   'unchanged_home_sha256_after_failures': home_hash,
                   'persistent_test_file_sha256': digest, 'validation_inputs_sha256': inputs}
        if inputs != {name: vm.sha256_file(root / name) for name in inputs}:
            raise RuntimeError('Update sources changed while QA was running; rerun the test')
        atomic_json(root / 'build/logs/arch-update-test-summary.json', summary)
    print('NEKO_MANAGED_UPDATE_TEST_PASSED', flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('init', 'status', 'prepare', 'activate', 'rollback', 'discard',
                                        'forget-previous', 'run', 'verify', 'test', 'test-boot'))
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--uefi', action='store_true')
    parser.add_argument('--timeout', type=int, default=1200)
    args = parser.parse_args(argv)
    if sys.platform != 'linux' or os.geteuid() == 0 or str(ROOT).startswith('/mnt/'):
        parser.error('use an ordinary user in the native Linux workspace')
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    if args.action not in ('run', 'verify') and (args.uefi or args.headless):
        parser.error('only run accepts display/firmware flags; update tests are always headless BIOS+UEFI')
    for tool in ('qemu-img', 'qemu-system-x86_64', 'mkfs.ext4'):
        if shutil.which(tool) is None:
            raise RuntimeError(f'Missing host tool: {tool}')
    with vm.file_lock(ROOT / 'build/arch/.build.lock', shared=True), vm.file_lock(ROOT / 'out/arch/.managed.lock'):
        if args.action == 'test':
            test_updates(ROOT, args.timeout)
            return
        if args.action == 'test-boot':
            from arch_boot_test import test_boot_guard
            test_boot_guard(ROOT)
            return
        manager = Manager(timeout=args.timeout)
        if args.action == 'init':
            with vm.file_lock(ROOT / 'out/arch/disks/.run-lock'):
                verified = vm.verify_images(ROOT)
                original = ROOT / 'out/arch/disks/system.qcow2'
                source = vm.prepare_persistent(ROOT, verified)[0] if os.path.lexists(original) else None
                before = vm.sha256_file(source) if source is not None else None
                manager.initialize(verified, source)
                if source is not None and vm.sha256_file(source) != before:
                    raise RuntimeError('Original VM changed during import')
        elif args.action == 'status':
            print(json.dumps(manager.load(), indent=2))
        elif args.action == 'run':
            manager.run(args.headless, args.uefi)
        elif args.action == 'verify':
            manager.verify(args.uefi)
        elif args.action == 'forget-previous':
            manager.forget_previous()
        else:
            getattr(manager, args.action)()


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f'NEKO_MANAGED_UPDATE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
