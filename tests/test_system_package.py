"""Exercise build-time NSPKG/1 creation, validation and rootfs assembly."""

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'system_package', Path(__file__).resolve().parents[1] / 'tools/system_package.py')
system_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(system_package)

SOURCE_HASH = hashlib.sha256(b'upstream source archive').hexdigest()


def make_archive(root, name, files, output=None, dependencies=()):
    stage = root / f'{name}-stage'
    (stage / 'usr').mkdir(parents=True)
    for path, body in files.items():
        target = stage / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(body, tuple):
            target.symlink_to(body[1])
        else:
            target.write_bytes(body)
    result = output or root / f'{name}.nspkg'
    system_package.build(stage, result, name, '1.2.3', 'x86_64', 'MIT',
                         SOURCE_HASH, dependencies, epoch=1_700_000_000)
    return result


class SystemPackageTests(unittest.TestCase):
    def test_deterministic_archive_and_install_with_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = make_archive(root, 'demo', {
                'usr/bin/demo': b'#!/bin/sh\necho demo\n',
                'usr/share/demo/read me.txt': b'data\n',
                'usr/lib/libdemo.so': ('link', '../share/demo/read me.txt'),
            })
            second = root / 'same.nspkg'
            stage = root / 'demo-stage'
            system_package.build(stage, second, 'demo', '1.2.3', 'x86_64',
                                 'MIT', SOURCE_HASH, epoch=1_700_000_000)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            manifest = system_package.verify(first)
            self.assertEqual(manifest['format'], 'NSPKG/1')
            self.assertEqual(manifest['package']['source_sha256'], SOURCE_HASH)
            self.assertEqual([entry['path'] for entry in manifest['files']],
                             sorted(entry['path'] for entry in manifest['files']))
            target = root / 'rootfs'
            target.mkdir()
            system_package.install([first], target)
            self.assertEqual((target / 'usr/bin/demo').read_bytes(),
                             b'#!/bin/sh\necho demo\n')
            self.assertEqual(os.readlink(target / 'usr/lib/libdemo.so'),
                             '../share/demo/read me.txt')
            self.assertEqual(json.loads((target / 'usr/share/nekoos/system-packages/'
                                         'demo.manifest').read_text()), manifest)

    def test_multiple_packages_share_directories_and_reject_collisions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            alpha = make_archive(root, 'alpha', {'usr/lib/libalpha.so': b'A'})
            beta = make_archive(root, 'beta', {'usr/lib/libbeta.so': b'B'},
                                dependencies=['alpha>=1.2.3'])
            target = root / 'rootfs'
            target.mkdir()
            system_package.install([alpha, beta], target)
            self.assertEqual((target / 'usr/lib/libalpha.so').read_bytes(), b'A')
            self.assertEqual((target / 'usr/lib/libbeta.so').read_bytes(), b'B')
            self.assertEqual(json.loads((target / 'usr/share/nekoos/system-packages/'
                                         'beta.manifest').read_text())['package']
                             ['dependencies'], ['alpha>=1.2.3'])
            with self.assertRaisesRegex(system_package.PackageError, 'already exists'):
                system_package.install([alpha], target)
            self.assertEqual((target / 'usr/lib/libalpha.so').read_bytes(), b'A')

    def test_conflicting_packages_and_existing_symlink_parent_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            alpha = make_archive(root, 'alpha', {'usr/bin/tool': b'A'})
            beta = make_archive(root, 'beta', {'usr/bin/tool': b'B'})
            target = root / 'rootfs'
            target.mkdir()
            with self.assertRaisesRegex(system_package.PackageError, 'path conflict'):
                system_package.install([alpha, beta], target)
            self.assertFalse((target / 'usr').exists())
            outside = root / 'outside'
            outside.mkdir()
            (target / 'usr').symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(system_package.PackageError, 'non-directory parent|already exists'):
                system_package.install([alpha], target)
            self.assertFalse((outside / 'bin/tool').exists())

    def test_reject_escaping_symlink_and_unsupported_source_type(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage = root / 'stage'
            (stage / 'usr/bin').mkdir(parents=True)
            (stage / 'usr/bin/escape').symlink_to('../../../etc/passwd')
            with self.assertRaisesRegex(system_package.PackageError, 'escapes'):
                system_package.build(stage, root / 'bad.nspkg', 'bad', '1.0',
                                     'x86_64', 'MIT', SOURCE_HASH)
            self.assertFalse((root / 'bad.nspkg').exists())
            (stage / 'usr/bin/escape').unlink()
            if hasattr(os, 'mkfifo'):
                os.mkfifo(stage / 'usr/bin/pipe')
                with self.assertRaisesRegex(system_package.PackageError, 'unsupported'):
                    system_package.build(stage, root / 'bad.nspkg', 'bad', '1.0',
                                         'x86_64', 'MIT', SOURCE_HASH)

    def test_tampered_payload_and_traversal_member_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            good = make_archive(root, 'demo', {'usr/bin/demo': b'correct'})
            with tarfile.open(good, 'r:') as archive:
                members = archive.getmembers()
                manifest = archive.extractfile(members[0]).read()
            for bad_name, bad_body in (
                    ('payload/usr/bin/demo', b'changed'),
                    ('payload/usr/bin/../../escape', b'correct')):
                tampered = root / f'tampered-{len(bad_body)}-{len(bad_name)}.nspkg'
                with tarfile.open(tampered, 'w') as archive:
                    info = tarfile.TarInfo('manifest.json')
                    info.size = len(manifest)
                    archive.addfile(info, io.BytesIO(manifest))
                    for original in members[1:]:
                        info = tarfile.TarInfo(bad_name if original.name.endswith('/demo')
                                               else original.name)
                        info.mode = original.mode
                        info.type = original.type
                        if original.isfile():
                            body = bad_body if original.name.endswith('/demo') else b''
                            info.size = len(body)
                            archive.addfile(info, io.BytesIO(body))
                        else:
                            archive.addfile(info)
                with self.assertRaises(system_package.PackageError):
                    system_package.verify(tampered)


if __name__ == '__main__':
    unittest.main()
