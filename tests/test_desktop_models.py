"""Compile and exercise the desktop's display-independent C models."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'rootfs/usr/bin'


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('cc'),
                     'requires a Linux C compiler')
class DesktopModelTests(unittest.TestCase):
    def run_model(self, name):
        with tempfile.TemporaryDirectory(prefix=f'neko-{name}-') as directory:
            program = Path(directory) / 'test-model'
            compile_result = subprocess.run(
                ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                 '-pedantic', str(ROOT / 'tests' / f'test_neko_{name}.c'),
                 str(SOURCE / f'neko-{name}.c'), '-o', str(program)],
                text=True, capture_output=True, timeout=30,
            )
            self.assertEqual(compile_result.returncode, 0,
                             compile_result.stderr)
            test_result = subprocess.run(
                [str(program)], text=True, capture_output=True, timeout=20,
            )
            self.assertEqual(test_result.returncode, 0,
                             test_result.stdout + test_result.stderr)

    def test_windows(self):
        self.run_model('windows')

    def test_files(self):
        self.run_model('files')

    def test_system(self):
        self.run_model('system')


if __name__ == '__main__':
    unittest.main()
