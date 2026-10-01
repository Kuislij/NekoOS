"""ISO integrity, read-only launch and separation from persistent user disks."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('arch_iso', Path(__file__).resolve().parents[1] / 'tools/arch_iso.py')
iso = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iso)


class LiveManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.directory = self.root / 'out/arch/iso'
        self.directory.mkdir(parents=True)
        for name in iso.NAMES:
            (self.directory / name).write_bytes(b'fixture\n')
        (self.directory / 'build-info.json').write_text(json.dumps({'format': 1, 'live_persistence': False}))
        (self.directory / 'boot-modes.txt').write_text(''.join(mode + '\n' for mode in iso.MODES))
        self.manifest()

    def manifest(self):
        (self.directory / 'SHA256SUMS').write_text(''.join(
            f'{hashlib.sha256((self.directory / name).read_bytes()).hexdigest()}  {name}\n' for name in iso.NAMES))

    def test_verified_manifest_and_unchanged_files(self):
        selected, metadata = iso.verify_iso(self.root)
        self.assertEqual(selected, self.directory / iso.NAMES[0])
        self.assertFalse(metadata['live_persistence'])

    def test_modified_image_is_rejected(self):
        (self.directory / iso.NAMES[0]).write_bytes(b'corrupt')
        with self.assertRaisesRegex(RuntimeError, 'checksum'):
            iso.verify_iso(self.root)

    def test_duplicate_missing_and_traversal_entries_are_rejected(self):
        original = (self.directory / 'SHA256SUMS').read_text()
        for value in (original + original.splitlines()[0] + '\n', original.split('\n', 1)[1],
                      original.replace(iso.NAMES[0], '../outside.iso')):
            (self.directory / 'SHA256SUMS').write_text(value)
            with self.assertRaises(RuntimeError):
                iso.verify_iso(self.root)

    @unittest.skipUnless(sys.platform == 'linux', 'POSIX symlink fixture')
    def test_symlinked_image_and_output_ancestor_are_rejected(self):
        image = self.directory / iso.NAMES[0]
        image.rename(self.directory / 'real.iso')
        image.symlink_to('real.iso')
        with self.assertRaises(RuntimeError):
            iso.verify_iso(self.root)
        image.unlink()
        (self.directory / 'real.iso').rename(image)
        self.directory.rename(self.directory.parent / 'real')
        self.directory.symlink_to('real', target_is_directory=True)
        with self.assertRaises(RuntimeError):
            iso.verify_iso(self.root)

    def test_persistent_live_metadata_is_rejected_even_with_valid_hashes(self):
        (self.directory / 'build-info.json').write_text(json.dumps({'format': 1, 'live_persistence': True}))
        self.manifest()
        with self.assertRaisesRegex(RuntimeError, 'metadata'):
            iso.verify_iso(self.root)

    @unittest.skipUnless(sys.platform == 'linux', 'Linux CLI')
    def test_no_build_missing_iso_never_calls_builder_or_qemu(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(iso, 'ROOT', Path(directory)), \
                patch.object(iso.os, 'geteuid', return_value=1000), patch.object(iso.subprocess, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'missing'):
                iso.main(['run', '--no-build'])
            run.assert_not_called()


class LiveCommandTests(unittest.TestCase):
    def test_all_four_modes_use_readonly_iso_without_host_kernel_or_user_disk(self):
        for usb in (False, True):
            for uefi in (False, True):
                command = iso.qemu_command(Path('/fixture/live.iso'), headless=True, usb=usb,
                    firmware=(Path('/fixture/code.fd'), Path('/fixture/private.fd')) if uefi else None)
                drives = [command[index + 1] for index, value in enumerate(command) if value == '-drive']
                live = [value for value in drives if '/fixture/live.iso' in value]
                self.assertEqual(len(live), 1)
                self.assertIn('readonly=on', live[0])
                self.assertNotIn('-kernel', command)
                self.assertNotIn('-initrd', command)
                self.assertNotIn('-no-reboot', command)
                self.assertFalse(any('system.qcow2' in value or '/dev/sd' in value for value in command))
                self.assertEqual(any('usb-storage' in value for value in command), usb)

    def test_only_generated_probe_can_be_writable_and_tests_stop_unexpected_reboot(self):
        command = iso.qemu_command(Path('/fixture/live.iso'), probe=Path('/fixture/internal-probe.img'), test=True)
        self.assertIn('-no-reboot', command)
        drives = [command[index + 1] for index, value in enumerate(command) if value == '-drive']
        writable = [value for value in drives if 'readonly=on' not in value]
        self.assertEqual(writable, ['file=/fixture/internal-probe.img,format=raw,if=virtio'])


if __name__ == '__main__':
    unittest.main()
