"""Exercise cached-image launch guards without building or starting a real VM."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

if sys.platform == 'linux':
    import fcntl

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'linux' and os.geteuid() != 0,
                     'run launcher tests as a regular Linux user')
class RunNoBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='neko-run-no-build-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ('scripts', 'configs', 'tools', 'bin', 'build', 'out/images', 'out/disks'):
            (self.root / name).mkdir(parents=True, exist_ok=True)
        for name in ('os', 'scripts/run.sh', 'scripts/common.sh', 'configs/sources.sh'):
            shutil.copyfile(ROOT / name, self.root / name)
        self.images = self.root / 'out/images'
        self.names = ('bzImage', 'initramfs.cpio.gz', 'bootstrap.cpio.gz', 'system-template.img')
        for name in self.names:
            (self.images / name).write_bytes(('test artifact: ' + name).encode())
        self.write_manifest()
        self.events = self.root / 'events'
        self.qemu_args = self.root / 'qemu-args'
        self.make_script('scripts/build.sh', 'echo BUILD >> "$TEST_EVENTS"\nexit 91\n')
        self.make_script('scripts/create-disk.sh', 'echo CREATE_STATE >> "$TEST_EVENTS"\n')
        self.make_script('scripts/create-system-disk.sh', 'echo CREATE_SYSTEM >> "$TEST_EVENTS"\n')
        self.make_script('bin/qemu-system-x86_64',
                         'echo QEMU >> "$TEST_EVENTS"\n'
                         'printf "%s\\n" "$@" > "$TEST_QEMU_ARGS"\n'
                         # A separate shared reader can enter, a builder cannot.
                         'flock -s -n "$TEST_ROOT/build/.lock" true || exit 92\n'
                         'if flock -n "$TEST_ROOT/build/.lock" true; then exit 93; fi\n')
        (self.root / 'tools/validate_image.py').write_text(
            'import os\nfrom pathlib import Path\n'
            'with Path(os.environ["TEST_EVENTS"]).open("a") as log:\n'
            '    log.write("VALIDATE\\n")\n')
        for name in ('state.img', 'system.img'):
            (self.root / 'out/disks' / name).write_bytes(('preserved ' + name).encode())
        self.env = dict(os.environ, PATH=str(self.root / 'bin') + os.pathsep + os.environ['PATH'],
                        TEST_ROOT=str(self.root), TEST_EVENTS=str(self.events),
                        TEST_QEMU_ARGS=str(self.qemu_args))

    def make_script(self, name, body):
        path = self.root / name
        path.write_text('#!/usr/bin/env bash\nset -eu\n' + body)
        path.chmod(0o755)

    def write_manifest(self, names=None):
        names = self.names if names is None else names
        (self.images / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.images / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in names))

    def launch(self, *args):
        return subprocess.run(['bash', str(self.root / 'os'), 'run', '--no-build', *args],
                              env=self.env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)

    def event_text(self):
        return self.events.read_text() if self.events.exists() else ''

    def assert_refused(self, result, reason):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(reason, result.stderr)
        self.assertNotIn('QEMU', self.event_text())
        self.assertNotIn('BUILD', self.event_text())

    def test_cached_ram_launch_checks_images_and_holds_shared_build_lock(self):
        result = self.launch('--ram')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.event_text(), 'VALIDATE\nQEMU\n')
        self.assertIn(str(self.images / 'initramfs.cpio.gz'), self.qemu_args.read_text())

    def test_cached_system_x11_launch_keeps_disk_behavior(self):
        result = self.launch('--system', '--x11')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.event_text(), 'VALIDATE\nCREATE_STATE\nCREATE_SYSTEM\nQEMU\n')
        args = self.qemu_args.read_text()
        self.assertIn(str(self.images / 'bootstrap.cpio.gz'), args)
        self.assertIn('neko.x11=1', args)
        self.assertIn('neko.system=required', args)
        for name in ('state.img', 'system.img'):
            self.assertIn(str(self.root / 'out/disks' / name), args)
            self.assertEqual((self.root / 'out/disks' / name).read_bytes(),
                             ('preserved ' + name).encode())

    def test_corrupted_kernel_is_refused(self):
        (self.images / 'bzImage').write_bytes(b'corrupted')
        self.assert_refused(self.launch('--ram'), 'checksum verification failed')
        self.assertNotIn('VALIDATE', self.event_text())

    def test_omitted_boot_checksum_is_refused(self):
        self.write_manifest(self.names[1:])
        self.assert_refused(self.launch('--ram'), 'checksum is missing for bzImage')

    def test_symlinked_boot_image_is_refused(self):
        image = self.images / 'bzImage'
        target = self.root / 'external-image'
        image.rename(target)
        image.symlink_to(target)
        self.assert_refused(self.launch('--ram'), 'Missing or unsafe image: bzImage')

    def test_symlinked_manifest_is_refused(self):
        manifest = self.images / 'SHA256SUMS'
        target = self.root / 'external-checksums'
        manifest.rename(target)
        manifest.symlink_to(target)
        self.assert_refused(self.launch('--ram'), 'Missing or unsafe image: SHA256SUMS')

    def test_manifest_path_outside_images_is_refused(self):
        with (self.images / 'SHA256SUMS').open('a') as manifest:
            manifest.write('0' * 64 + '  ../external-image\n')
        self.assert_refused(self.launch('--ram'), 'malformed or unsafe entry')

    def test_duplicate_manifest_entry_is_refused(self):
        manifest = self.images / 'SHA256SUMS'
        with manifest.open('a') as stream:
            stream.write(manifest.read_text().splitlines()[0] + '\n')
        self.assert_refused(self.launch('--ram'), 'manifest repeats bzImage')

    def test_missing_selected_system_bootstrap_is_refused(self):
        (self.images / 'bootstrap.cpio.gz').unlink()
        self.assert_refused(self.launch('--system'), 'Missing or unsafe image: bootstrap.cpio.gz')

    def test_valid_hashes_do_not_bypass_real_image_validator(self):
        shutil.copyfile(ROOT / 'tools/validate_image.py', self.root / 'tools/validate_image.py')
        self.assert_refused(self.launch('--ram'), 'Image contents failed validation')

    def test_active_builder_blocks_cached_launch(self):
        with (self.root / 'build/.lock').open('a+b') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assert_refused(self.launch('--ram'), 'Another build is changing the images')


if __name__ == '__main__':
    unittest.main()
