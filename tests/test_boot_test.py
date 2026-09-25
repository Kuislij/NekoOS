"""Failure-path checks for the VM test harness; no guest image required."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'boot_test', Path(__file__).resolve().parents[1] / 'tools/boot_test.py'
)
boot_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot_test)


@unittest.skipUnless(sys.platform == 'linux', 'requires Linux sha256sum')
class BootHarnessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.images = self.root / 'out/images'
        self.images.mkdir(parents=True)
        lines = []
        for name in ('bzImage', 'initramfs.cpio.gz'):
            data = b'test fixture'
            (self.images / name).write_bytes(data)
            lines.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        (self.images / 'SHA256SUMS').write_text(''.join(lines))
        self.root_patch = patch.object(boot_test, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_corrupt_image_is_rejected_before_launch(self):
        (self.images / 'bzImage').write_bytes(b'corrupted')
        with self.assertRaises(subprocess.CalledProcessError):
            boot_test.boot(argparse.Namespace(no_build=True, timeout=1))
        self.assertFalse((self.root / 'build/logs/boot-test.log').exists())

    def test_timeout_reaps_the_child_process(self):
        original_popen = subprocess.Popen
        original_run = subprocess.run
        children = []

        def launch(command, **kwargs):
            if command[0] == 'qemu-system-x86_64':
                command = [sys.executable, '-c', 'import time; time.sleep(30)']
                child = original_popen(command, **kwargs)
                children.append(child)
                return child
            return original_popen(command, **kwargs)

        def run(command, **kwargs):
            if command[0] == sys.executable:
                return subprocess.CompletedProcess(command, 0)
            return original_run(command, **kwargs)

        with patch.object(boot_test.subprocess, 'Popen', side_effect=launch), \
             patch.object(boot_test.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'did not complete'):
                boot_test.boot(argparse.Namespace(no_build=True, timeout=0.2))
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())


if __name__ == '__main__':
    unittest.main()
