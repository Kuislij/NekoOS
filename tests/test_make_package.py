"""Validate the package contract consumed by the guest installer."""
import hashlib
import importlib.util
from pathlib import Path
import tarfile
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'make_package', Path(__file__).resolve().parents[1] / 'tools/make_package.py'
)
make_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_package)


class PackageTests(unittest.TestCase):
    def test_archive_is_deterministic_and_has_one_verified_command(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'program'
            source.write_bytes(b'#!/bin/sh\necho ready\n')
            first, second = root / 'first.npkg', root / 'second.npkg'
            for output in (first, second):
                make_package.make_package(source, output, 'demo', '1.2.0',
                                          'NOASSERTION', 1790035200)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with tarfile.open(first, 'r:gz') as archive:
                self.assertEqual(archive.getnames(), ['manifest', 'payload'])
                self.assertTrue(all(member.isfile() for member in archive))
                manifest = archive.extractfile('manifest').read().decode('ascii')
                payload = archive.extractfile('payload').read()
            self.assertIn('path=/usr/local/bin/demo\n', manifest)
            self.assertTrue(manifest.startswith('NEKOPKG/2\n'))
            self.assertIn(f'size={len(payload)}\n', manifest)
            self.assertIn(f'sha256={hashlib.sha256(payload).hexdigest()}\n', manifest)

    def test_rejects_unsafe_names_and_symlink_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'program'
            source.write_bytes(b'hello')
            link = root / 'link'
            link.symlink_to(source)
            with self.assertRaises(ValueError):
                make_package.make_package(source, root / 'bad.npkg', '../bad',
                                          '1.0', 'NOASSERTION')
            with self.assertRaises(ValueError):
                make_package.make_package(link, root / 'bad.npkg', 'demo',
                                          '1.0', 'NOASSERTION')
            self.assertFalse((root / 'bad.npkg').exists())

    def test_dependencies_are_sorted_and_legacy_format_remains_available(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'program'
            source.write_bytes(b'#!/bin/sh\nexit 0\n')
            modern = root / 'modern.npkg'
            make_package.make_package(
                source, modern, 'demo', '2.0.0', 'NOASSERTION',
                dependencies=['zebra>=1.2.0', 'alpha>=0.1.0'])
            with tarfile.open(modern, 'r:gz') as archive:
                manifest = archive.extractfile('manifest').read().decode('ascii')
            self.assertIn('depends=alpha>=0.1.0,zebra>=1.2.0\n', manifest)
            legacy = root / 'legacy.npkg'
            make_package.make_package(source, legacy, 'demo', '1.0',
                                      'NOASSERTION', format_version=1)
            with tarfile.open(legacy, 'r:gz') as archive:
                manifest = archive.extractfile('manifest').read().decode('ascii')
            self.assertTrue(manifest.startswith('NEKOPKG/1\n'))
            self.assertIn('depends=none\n', manifest)
            with self.assertRaises(ValueError):
                make_package.make_package(source, root / 'invalid.npkg', 'demo',
                                          '2.0', 'NOASSERTION')
            with self.assertRaises(ValueError):
                make_package.make_package(
                    source, root / 'invalid.npkg', 'demo', '2.0.0',
                    'NOASSERTION', dependencies=['demo>=1.0.0'])


if __name__ == '__main__':
    unittest.main()
