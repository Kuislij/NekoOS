"""Managed updates must preserve the selected root and user data on failure."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'arch_update', Path(__file__).resolve().parents[1] / 'tools/arch_update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class ReleaseTests(unittest.TestCase):
    def test_release_rejects_commands_urls_and_invalid_dates(self):
        release = json.loads((update.ROOT / 'arch/releases/testing.json').read_text())
        self.assertEqual(update.release_record(release)['snapshot'], '2026/10/01')
        for changes in ({'snapshot': '2026/10/01; touch /tmp/unsafe'},
                        {'snapshot': '2026/02/30'}, {'channel': 'stable'},
                        {'databases': {'core': 'https://untrusted.invalid', 'extra': '0' * 64}},
                        {'architecture': 'other'}, {'server': 'https://untrusted.invalid'}):
            with self.subTest(changes=changes), self.assertRaises((RuntimeError, ValueError)):
                update.release_record({**release, **changes})


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('qemu-img'),
                     'requires Linux and qemu-img')
class ManagedUpdateTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix='neko-update-guards-')
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.manager = update.Manager(self.root)
        self.old = 'gen-' + '1' * 32
        self.new = 'gen-' + '2' * 32
        self.make_disk(self.old)
        self.manager.home.write_bytes(b'current user files')
        self.release = json.loads((update.ROOT / 'arch/releases/testing.json').read_text())
        (self.root / 'arch/releases').mkdir(parents=True)
        (self.root / 'arch/releases/testing.json').write_text(json.dumps(self.release))
        self.facts = {'KERNEL': '7.2.7-arch1-1', 'PACKAGES': 'a' * 64}
        self.state = {'format': 1, 'active': self.old, 'previous': None, 'pending': None,
                      'generations': {self.old: {'snapshot': 'imported', 'seal': None,
                                                  'facts': self.facts}}}
        self.manager.save(self.state)
        self.initial = self.manager.state_path.read_bytes()

    def make_disk(self, identifier):
        subprocess.run(['qemu-img', 'create', '-q', '-f', 'qcow2',
                        str(self.manager.disk(identifier)), '64M'], check=True)

    def ready(self):
        self.make_disk(self.new)
        self.state['generations'][self.new] = {
            'snapshot': self.release['snapshot'],
            'seal': update.vm.sha256_file(self.manager.disk(self.new)),
            'facts': {**self.facts, 'PACKAGES': 'b' * 64}}
        self.state['pending'] = {'id': self.new, 'phase': 'ready', 'release': self.release}
        self.manager.save(self.state)

    def test_activation_and_rollback_keep_home_and_both_complete_roots(self):
        self.ready()
        root_hash = update.vm.sha256_file(self.manager.disk(self.old))
        self.manager.activate()
        self.assertEqual(self.manager.load()['active'], self.new)
        self.manager.home.write_bytes(b'a file created after updating')
        home_hash = update.vm.sha256_file(self.manager.home)
        self.manager.rollback()
        restored = self.manager.load()
        self.assertEqual((restored['active'], restored['previous']), (self.old, self.new))
        self.assertEqual(update.vm.sha256_file(self.manager.home), home_hash)
        self.assertEqual(update.vm.sha256_file(self.manager.disk(self.old)), root_hash)
        self.manager.rollback()
        self.assertEqual(self.manager.load()['active'], self.new)

    def test_failed_atomic_activation_keeps_previous_selection(self):
        self.ready()
        before = self.manager.state_path.read_bytes()
        with patch.object(update.os, 'replace', side_effect=OSError('simulated power loss')):
            with self.assertRaises(OSError):
                self.manager.activate()
        self.assertEqual(self.manager.state_path.read_bytes(), before)
        self.assertEqual(self.manager.load()['active'], self.old)
        self.assertTrue(self.manager.disk(self.new).exists())
        self.assertEqual(list(self.manager.directory.glob('.state-*')), [])

    def test_modified_candidate_is_refused_before_activation(self):
        self.ready()
        before = self.manager.state_path.read_bytes()
        with self.manager.disk(self.new).open('ab') as stream:
            stream.write(b'modified after verification')
        with self.assertRaisesRegex(RuntimeError, 'checksum failed'):
            self.manager.activate()
        self.assertEqual(self.manager.state_path.read_bytes(), before)
        self.assertEqual(self.manager.home.read_bytes(), b'current user files')

    def test_ready_candidate_requires_seal_and_package_facts(self):
        self.ready()
        for field, value in (('seal', None), ('facts', {})):
            with self.subTest(field=field):
                bad = copy.deepcopy(self.state)
                bad['generations'][self.new][field] = value
                self.manager.save(bad)
                before = self.manager.state_path.read_bytes()
                with self.assertRaisesRegex(RuntimeError, 'lacks its verification'):
                    self.manager.activate()
                self.assertEqual(self.manager.state_path.read_bytes(), before)

    def test_copy_failure_and_missing_pending_disk_are_discardable(self):
        root_hash = update.vm.sha256_file(self.manager.disk(self.old))
        with patch.object(self.manager, 'require_space'), patch.object(update, 'clone',
                side_effect=OSError('simulated ENOSPC during copy')):
            with self.assertRaises(OSError):
                self.manager.prepare()
        pending = self.manager.load()['pending']
        self.assertEqual(pending['phase'], 'failed')
        self.assertFalse(self.manager.disk(pending['id']).exists())
        with self.assertRaisesRegex(RuntimeError, 'completely tested'):
            self.manager.activate()
        self.manager.discard()
        self.assertIsNone(self.manager.load()['pending'])
        self.assertEqual(update.vm.sha256_file(self.manager.disk(self.old)), root_hash)
        self.assertEqual(self.manager.home.read_bytes(), b'current user files')

    def test_low_space_is_refused_before_transaction_or_disk_creation(self):
        usage = shutil._ntuple_diskusage(100, 99, 1)
        with patch.object(update.shutil, 'disk_usage', return_value=usage):
            with self.assertRaisesRegex(RuntimeError, '24 GiB'):
                self.manager.prepare()
        self.assertEqual(self.manager.state_path.read_bytes(), self.initial)
        self.assertEqual(len(list(self.manager.directory.glob('gen-*.qcow2'))), 1)

    def test_candidate_and_home_symlinks_or_hardlinks_are_refused(self):
        self.ready()
        outside = self.root / 'outside.qcow2'
        self.manager.disk(self.new).rename(outside)
        self.manager.disk(self.new).symlink_to(outside)
        before = outside.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'Unsafe file'):
            self.manager.activate()
        self.assertEqual(outside.read_bytes(), before)
        self.manager.disk(self.new).unlink()
        outside.rename(self.manager.disk(self.new))
        os.link(self.manager.home, self.root / 'shared-home')
        with self.assertRaisesRegex(RuntimeError, 'Unsafe file'):
            self.manager.rollback()
        self.assertEqual(self.manager.home.read_bytes(), b'current user files')

    def test_external_backing_disk_is_refused(self):
        self.ready()
        self.manager.disk(self.new).unlink()
        subprocess.run(['qemu-img', 'create', '-q', '-f', 'qcow2', '-F', 'qcow2',
                        '-b', str(self.manager.disk(self.old)), str(self.manager.disk(self.new))], check=True)
        before = self.manager.state_path.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'external backing'):
            self.manager.activate()
        self.assertEqual(self.manager.state_path.read_bytes(), before)

    def test_unsafe_duplicate_and_missing_generation_references_are_refused(self):
        for changes in ({'active': '../external'}, {'active': self.new},
                        {'previous': self.old}, {'active': ['unsafe']}):
            with self.subTest(changes=changes):
                self.manager.save({**self.state, **changes})
                with self.assertRaises(RuntimeError):
                    self.manager.load()
        self.assertEqual(self.manager.home.read_bytes(), b'current user files')

    def test_retained_generation_prevents_automatic_disk_growth(self):
        self.ready()
        self.manager.activate()
        before = self.manager.state_path.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'retained'):
            self.manager.prepare()
        self.assertEqual(self.manager.state_path.read_bytes(), before)
        self.manager.forget_previous()
        self.assertFalse(self.manager.disk(self.old).exists())
        self.assertTrue(self.manager.disk(self.new).exists())
        self.assertEqual(self.manager.home.read_bytes(), b'current user files')

    def test_modified_previous_generation_blocks_rollback(self):
        self.ready()
        self.manager.activate()
        before = self.manager.state_path.read_bytes()
        with self.manager.disk(self.old).open('ab') as stream:
            stream.write(b'corruption')
        with self.assertRaisesRegex(RuntimeError, 'checksum failed'):
            self.manager.rollback()
        self.assertEqual(self.manager.state_path.read_bytes(), before)

    def test_missing_previous_seal_cannot_bypass_rollback_verification(self):
        self.ready()
        self.manager.activate()
        state = self.manager.load()
        state['generations'][self.old]['seal'] = None
        self.manager.save(state)
        before = self.manager.state_path.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'missing its verification seal'):
            self.manager.rollback()
        self.assertEqual(self.manager.state_path.read_bytes(), before)

    def test_host_lock_refuses_parallel_update(self):
        lock = self.manager.directory / '.managed.lock'
        with update.vm.file_lock(lock):
            with self.assertRaisesRegex(RuntimeError, 'Another build or VM'):
                with update.vm.file_lock(lock):
                    self.fail('a second updater obtained the lock')
        self.assertEqual(self.manager.state_path.read_bytes(), self.initial)


if __name__ == '__main__':
    unittest.main()
