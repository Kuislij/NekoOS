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


if __name__ == '__main__':
    unittest.main()
