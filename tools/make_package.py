#!/usr/bin/env python3
"""Create a deterministic NekoPkg/1 archive containing one executable."""
import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import re
import sys
import tarfile
import tempfile

MAX_PAYLOAD = 16 * 1024 * 1024
NAME = re.compile(r'[a-z][a-z0-9-]{0,63}\Z')
VERSION = re.compile(r'[0-9][A-Za-z0-9.+-]{0,63}\Z')
LICENSE = re.compile(r'[A-Za-z0-9][A-Za-z0-9.+-]{0,63}\Z')


def make_package(source, output, name, version, license_id, epoch=0):
    if not NAME.fullmatch(name) or not VERSION.fullmatch(version):
        raise ValueError('invalid package name or version')
    if not LICENSE.fullmatch(license_id):
        raise ValueError('license must be one SPDX identifier or NOASSERTION')
    if source.is_symlink() or not source.is_file():
        raise ValueError('payload must be a regular file, not a symlink')
    if source.resolve() == output.resolve():
        raise ValueError('input and output must differ')
    payload = source.read_bytes()
    if not payload or len(payload) > MAX_PAYLOAD:
        raise ValueError('payload must be between 1 byte and 16 MiB')
    if epoch < 0 or epoch > 0o77777777777:
        raise ValueError('invalid archive timestamp')
    manifest = ('NEKOPKG/1\n'
                f'name={name}\nversion={version}\narch=x86_64\n'
                f'license={license_id}\ndepends=none\n'
                f'path=/usr/local/bin/{name}\nsize={len(payload)}\n'
                f'sha256={hashlib.sha256(payload).hexdigest()}\n').encode('ascii')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile('wb', dir=output.parent,
                                         prefix=f'.{output.name}.', suffix='.tmp',
                                         delete=False) as raw:
            temporary = Path(raw.name)
            with gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
                    for member_name, body, mode in (('manifest', manifest, 0o644),
                                                    ('payload', payload, 0o755)):
                        info = tarfile.TarInfo(member_name)
                        info.size = len(body)
                        info.mode = mode
                        info.uid = info.gid = 0
                        info.mtime = epoch
                        archive.addfile(info, io.BytesIO(body))
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--license', required=True, dest='license_id')
    parser.add_argument('--file', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        make_package(args.file, args.output, args.name, args.version,
                     args.license_id, int(os.environ.get('SOURCE_DATE_EPOCH', '0')))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f'PACKAGE_READY: {args.output}')


if __name__ == '__main__':
    sys.exit(main())
