#!/usr/bin/env python3
"""Create deterministic NekoPkg archives with a command and optional resources."""
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
MAX_TOTAL = 32 * 1024 * 1024
MAX_RESOURCES = 64
NAME = re.compile(r'[a-z][a-z0-9-]{0,63}\Z')
VERSION = re.compile(r'[0-9][A-Za-z0-9.+-]{0,63}\Z')
LICENSE = re.compile(r'[A-Za-z0-9][A-Za-z0-9.+-]{0,63}\Z')
PART = r'(?:0|[1-9][0-9]{0,3})'
SEMVER = re.compile(rf'{PART}\.{PART}\.{PART}\Z')
DEPENDENCY = re.compile(rf'([a-z][a-z0-9-]{{0,63}})>=({PART}\.{PART}\.{PART})\Z')
RESOURCE_PART = re.compile(r'[A-Za-z0-9_][A-Za-z0-9._+-]{0,63}\Z')


def resource_name(value):
    """Return the archive member name for a safe package-relative path."""
    if (not value or len(value) > 90 or
            not value.startswith(('share/', 'lib/')) or not all(
            RESOURCE_PART.fullmatch(part) for part in value.split('/'))):
        raise ValueError(f'invalid resource path: {value}')
    return f'files/{value}'


def resource_spec(value):
    destination, separator, source = value.partition('=')
    if not separator or not source:
        raise ValueError('resources must be specified as DESTINATION=SOURCE')
    return destination, Path(source)


def make_package(source, output, name, version, license_id, epoch=0,
                 dependencies=(), format_version=2, resources=(), programs=()):
    if not NAME.fullmatch(name) or not VERSION.fullmatch(version):
        raise ValueError('invalid package name or version')
    if format_version not in (1, 2, 3):
        raise ValueError('format version must be 1, 2 or 3')
    if format_version in (2, 3) and not SEMVER.fullmatch(version):
        raise ValueError('NekoPkg/2 and /3 require MAJOR.MINOR.PATCH version')
    if format_version == 1 and dependencies:
        raise ValueError('NekoPkg/1 cannot declare dependencies')
    if format_version != 3 and (resources or programs):
        raise ValueError('additional files require NekoPkg/3')
    if len(dependencies) > 8:
        raise ValueError('at most eight dependencies are supported')
    parsed_dependencies = {}
    for dependency in dependencies:
        match = DEPENDENCY.fullmatch(dependency)
        if not match or match.group(1) == name or match.group(1) in parsed_dependencies:
            raise ValueError(f'invalid or duplicate dependency: {dependency}')
        parsed_dependencies[match.group(1)] = match.group(2)
    depends = ','.join(f'{key}>={parsed_dependencies[key]}'
                       for key in sorted(parsed_dependencies)) or 'none'
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
    members = [('payload', payload, 0o755)]
    seen = set()
    for specifications, mode in ((resources, 0o644), (programs, 0o755)):
        for destination, file_source in specifications:
            member_name = resource_name(destination)
            if member_name in seen:
                raise ValueError(f'duplicate resource path: {destination}')
            seen.add(member_name)
            if file_source.is_symlink() or not file_source.is_file():
                raise ValueError(f'resource must be a regular file: {file_source}')
            if file_source.resolve() == output.resolve():
                raise ValueError('input and output must differ')
            body = file_source.read_bytes()
            if len(body) > MAX_PAYLOAD:
                raise ValueError('resource must be at most 16 MiB')
            members.append((member_name, body, mode))
    if len(seen) > MAX_RESOURCES:
        raise ValueError('at most 64 resources are supported')
    if sum(len(body) for _, body, _ in members) > MAX_TOTAL:
        raise ValueError('package files must total at most 32 MiB')
    members[1:] = sorted(members[1:], key=lambda member: member[0])
    manifest = (f'NEKOPKG/{format_version}\n'
                f'name={name}\nversion={version}\narch=x86_64\n'
                f'license={license_id}\ndepends={depends}\n'
                f'path=/usr/local/bin/{name}\nsize={len(payload)}\n'
                f'sha256={hashlib.sha256(payload).hexdigest()}\n')
    if format_version == 3:
        manifest += f'files={len(members) - 1}\n'
        for member_name, body, mode in members[1:]:
            manifest += (f'file={member_name}|{len(body)}|'
                         f'{hashlib.sha256(body).hexdigest()}|{mode:o}\n')
    manifest = manifest.encode('ascii')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile('wb', dir=output.parent,
                                         prefix=f'.{output.name}.', suffix='.tmp',
                                         delete=False) as raw:
            temporary = Path(raw.name)
            with gzip.GzipFile(fileobj=raw, mode='wb', filename='', mtime=0) as compressed:
                with tarfile.open(fileobj=compressed, mode='w', format=tarfile.USTAR_FORMAT) as archive:
                    for member_name, body, mode in [('manifest', manifest, 0o644), *members]:
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
    parser.add_argument('--depends', action='append', default=[], metavar='NAME>=VERSION')
    parser.add_argument('--resource', action='append', default=[], metavar='DEST=SOURCE',
                        help='add a read-only file below files/ (NekoPkg/3)')
    parser.add_argument('--program', action='append', default=[], metavar='DEST=SOURCE',
                        help='add an executable below files/ (NekoPkg/3)')
    parser.add_argument('--format', type=int, choices=(1, 2, 3), default=None,
                        dest='format_version')
    parser.add_argument('--file', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        resources = [resource_spec(value) for value in args.resource]
        programs = [resource_spec(value) for value in args.program]
        format_version = args.format_version
        if format_version is None:
            format_version = 3 if (resources or programs) else 2
        make_package(args.file, args.output, args.name, args.version,
                     args.license_id, int(os.environ.get('SOURCE_DATE_EPOCH', '0')),
                     args.depends, format_version, resources, programs)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f'PACKAGE_READY: {args.output}')


if __name__ == '__main__':
    sys.exit(main())
