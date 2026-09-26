"""Exercise the NekoPkg/3 archive contract and hostile input rejection."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'make_package', Path(__file__).resolve().parents[1] / 'tools/make_package.py'
)
make_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_package)


class MultiFilePackageTests(unittest.TestCase):
    def test_resources_are_sorted_verified_and_reproducible(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            command = root / 'command'
            message = root / 'message'
            helper = root / 'helper'
            command.write_bytes(b'#!/bin/sh\necho ready\n')
            message.write_bytes(b'hello from share\n')
            helper.write_bytes(b'#!/bin/sh\nexit 0\n')
            first, second = root / 'first.npkg', root / 'second.npkg'
            for output in (first, second):
                make_package.make_package(
                    command, output, 'demo', '1.0.0', 'NOASSERTION', 1234,
                    format_version=3,
                    resources=[('share/message.txt', message)],
                    programs=[('lib/helper', helper)])
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with tarfile.open(first, 'r:gz') as archive:
                self.assertEqual(archive.getnames(), [
                    'manifest', 'payload', 'files/lib/helper',
                    'files/share/message.txt'])
                manifest = archive.extractfile('manifest').read().decode('ascii')
                self.assertIn('files=2\n', manifest)
                self.assertIn(
                    'file=files/lib/helper|17|'
                    f'{hashlib.sha256(helper.read_bytes()).hexdigest()}|755\n',
                    manifest)
                self.assertIn(
                    'file=files/share/message.txt|17|'
                    f'{hashlib.sha256(message.read_bytes()).hexdigest()}|644\n',
                    manifest)
                self.assertEqual(archive.getmember('files/lib/helper').mode, 0o755)
                self.assertEqual(archive.getmember('files/share/message.txt').mode, 0o644)

    def test_rejects_escape_conflicts_and_legacy_extra_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source'
            source.write_bytes(b'valid')
            linked = root / 'link'
            linked.symlink_to(source)
            output = root / 'bad.npkg'
            for destination in ('../etc/passwd', '/usr/local/share/demo',
                                'share/../private', 'share//name',
                                'share/name with spaces', 'other/file'):
                with self.subTest(destination=destination), self.assertRaises(ValueError):
                    make_package.make_package(
                        source, output, 'demo', '1.0.0', 'NOASSERTION',
                        format_version=3, resources=[(destination, source)])
            with self.assertRaises(ValueError):
                make_package.make_package(
                    source, output, 'demo', '1.0.0', 'NOASSERTION',
                    format_version=3, resources=[('share/a', source)],
                    programs=[('share/a', source)])
            with self.assertRaises(ValueError):
                make_package.make_package(
                    source, output, 'demo', '1.0.0', 'NOASSERTION',
                    format_version=3, resources=[('share/a', linked)])
            with self.assertRaises(ValueError):
                make_package.make_package(
                    source, output, 'demo', '1.0.0', 'NOASSERTION',
                    format_version=2, resources=[('share/a', source)])
            self.assertFalse(output.exists())

    @unittest.skipUnless(os.name == 'posix' and shutil.which('tar') and
                         shutil.which('flock') and shutil.which('sha256sum'),
                         'requires a Linux shell and package applets')
    def test_installer_switches_command_and_public_resource_together(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            local = root / 'usr/local'
            for folder in ('bin', 'lib', 'share'):
                (local / folder).mkdir(parents=True, exist_ok=True)
            source_script = (Path(__file__).resolve().parents[1] /
                             'rootfs/usr/bin/neko-pkg').read_text()
            source_script = source_script.replace(
                'base=/usr/local/lib/neko-pkg', f'base={local}/lib/neko-pkg')
            for key in ('bin', 'lib', 'share'):
                source_script = source_script.replace(
                    f'{key}=/usr/local/{key}', f'{key}={local}/{key}')
            source_script = source_script.replace(
                "grep -q ' /state ext4 ' /proc/mounts || die 'Start NekoOS with its persistent disk (without --ram).'",
                ':')
            script = root / 'neko-pkg'
            script.write_text(source_script)
            command = root / 'command'
            command.write_text('#!/bin/sh\ncat "$(dirname "$(readlink -f "$0")")/files/share/message.txt"\n')
            first_message, second_message = root / 'first.txt', root / 'second.txt'
            first_message.write_text('first\n')
            second_message.write_text('second\n')
            archives = []
            for version, message in (('1.0.0', first_message),
                                     ('1.1.0', second_message)):
                archive = root / f'demo-{version}.npkg'
                make_package.make_package(
                    command, archive, 'demo', version, 'NOASSERTION',
                    format_version=3, resources=[('share/message.txt', message)])
                archives.append(archive)

            def run_pkg(*arguments, success=True):
                result = subprocess.run(
                    ['sh', str(script), *map(str, arguments)],
                    capture_output=True, text=True,
                    env={**os.environ, 'PATH': f'{local}/bin:' + os.environ['PATH']})
                self.assertEqual(result.returncode == 0, success, result.stderr)
                return result

            manual = local / 'share/demo'
            manual.mkdir()
            run_pkg('install', archives[0], success=False)
            self.assertTrue(manual.is_dir())
            self.assertFalse((local / 'bin/demo').exists())
            manual.rmdir()

            run_pkg('install', archives[0])
            public = local / 'share/demo/message.txt'
            self.assertEqual(public.read_text(), 'first\n')
            self.assertEqual(subprocess.check_output([local / 'bin/demo']), b'first\n')
            run_pkg('verify', 'demo')
            active_link = local / 'lib/neko-pkg/active/demo'
            first_target = active_link.readlink()
            run_pkg('upgrade', archives[1])
            self.assertNotEqual(active_link.readlink(), first_target)
            self.assertEqual(public.read_text(), 'second\n')
            self.assertEqual(subprocess.check_output([local / 'bin/demo']), b'second\n')
            run_pkg('verify', 'demo')
            public.write_text('damaged\n')
            run_pkg('verify', 'demo', success=False)
            run_pkg('remove', 'demo')
            self.assertFalse((local / 'bin/demo').is_symlink())
            self.assertFalse((local / 'share/demo').is_symlink())
            self.assertFalse((local / 'lib/demo').is_symlink())

            legacy_command = root / 'legacy-command'
            legacy_command.write_text('#!/bin/sh\necho legacy\n')
            legacy_archive = root / 'legacy.npkg'
            make_package.make_package(
                legacy_command, legacy_archive, 'demo', '0.9.0',
                'NOASSERTION', format_version=2)
            run_pkg('install', legacy_archive)
            self.assertEqual(subprocess.check_output([local / 'bin/demo']), b'legacy\n')
            run_pkg('upgrade', archives[0])
            self.assertEqual(public.read_text(), 'first\n')
            self.assertEqual(subprocess.check_output([local / 'bin/demo']), b'first\n')
            run_pkg('verify', 'demo')
            run_pkg('remove', 'demo')


if __name__ == '__main__':
    unittest.main()
