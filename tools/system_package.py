#!/usr/bin/env python3
"""Build and safely assemble deterministic NSPKG/1 system packages.

These build-time archives are intentionally separate from the guest's NekoPkg
format. A source tree contains paths below ``usr/``; installation never runs
package scripts and never follows package or rootfs symlinks while writing.
"""

import argparse
import hashlib
import io
from itertools import zip_longest
import json
import os
from pathlib import Path
import re
import stat
import sys
import tarfile
import tempfile

FORMAT = 'NSPKG/1'
MAX_MANIFEST = 32 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_FILE = 1024 * 1024 * 1024
MAX_TOTAL = 4 * 1024 * 1024 * 1024
NAME = re.compile(r'[a-z][a-z0-9+.-]{0,63}\Z')
VERSION = re.compile(r'[0-9][A-Za-z0-9._+~-]{0,127}\Z')
ARCH = re.compile(r'[A-Za-z0-9_+-]{1,32}\Z')
LICENSE = re.compile(r'[A-Za-z0-9][A-Za-z0-9.+-]{0,63}\Z')
SHA256 = re.compile(r'[0-9a-f]{64}\Z')
DEPENDENCY = re.compile(r'([a-z][a-z0-9+.-]{0,63})(?:>=([0-9][A-Za-z0-9._+~-]{0,127}))?\Z')


class PackageError(ValueError):
    """The archive or requested installation is invalid."""


def _check_path(path):
    if (not isinstance(path, str) or not (path == 'usr' or path.startswith('usr/')) or
            len(path.encode('utf-8')) > 4096 or '\\' in path or
            any(ord(char) < 32 or ord(char) == 127 for char in path)):
        raise PackageError(f'unsafe package path: {path!r}')
    components = path.split('/')
    if any(not component or component in ('.', '..') or
           len(component.encode('utf-8')) > 255 for component in components):
        raise PackageError(f'unsafe package path: {path!r}')
    return components


def _check_link(path, target):
    if (not isinstance(target, str) or not target or target.startswith('/') or
            '\\' in target or len(target.encode('utf-8')) > 4096 or
            any(ord(char) < 32 or ord(char) == 127 for char in target)):
        raise PackageError(f'unsafe symlink target for {path}: {target!r}')
    stack = path.split('/')[:-1]
    for part in target.split('/'):
        if part in ('', '.'):
            continue
        if part == '..':
            if len(stack) == 1:
                raise PackageError(f'symlink escapes /usr: {path} -> {target}')
            stack.pop()
        else:
            if len(part.encode('utf-8')) > 255:
                raise PackageError(f'unsafe symlink target: {target!r}')
            stack.append(part)
    if len(stack) < 2:
        raise PackageError(f'symlink escapes /usr: {path} -> {target}')


def _json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True,
                       separators=(',', ':')) + '\n').encode('utf-8')


def _unique_json(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PackageError(f'duplicate manifest key: {key}')
        result[key] = value
    return result


def _validate_metadata(name, version, arch, license_id, dependencies,
                       source_sha256):
    if not isinstance(name, str) or not NAME.fullmatch(name):
        raise PackageError(f'invalid package name: {name!r}')
    if not isinstance(version, str) or not VERSION.fullmatch(version):
        raise PackageError(f'invalid package version: {version!r}')
    if not isinstance(arch, str) or not ARCH.fullmatch(arch):
        raise PackageError(f'invalid package architecture: {arch!r}')
    if not isinstance(license_id, str) or not LICENSE.fullmatch(license_id):
        raise PackageError(f'invalid license identifier: {license_id!r}')
    if not isinstance(source_sha256, str) or not SHA256.fullmatch(source_sha256):
        raise PackageError('source_sha256 must be a lowercase SHA-256 digest')
    if not isinstance(dependencies, list) or len(dependencies) > 256:
        raise PackageError('invalid dependency list')
    seen = set()
    for dependency in dependencies:
        match = DEPENDENCY.fullmatch(dependency) if isinstance(dependency, str) else None
        if not match or match.group(1) == name or match.group(1) in seen:
            raise PackageError(f'invalid or duplicate dependency: {dependency!r}')
        seen.add(match.group(1))
    if dependencies != sorted(dependencies):
        raise PackageError('dependencies must be sorted')


def _hash_file(path):
    digest = hashlib.sha256()
    total = 0
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
    with os.fdopen(os.open(path, flags), 'rb') as source:
        while block := source.read(1024 * 1024):
            total += len(block)
            if total > MAX_FILE:
                raise PackageError(f'file exceeds 1 GiB: {path}')
            digest.update(block)
    return total, digest.hexdigest()


def _open_source(path):
    """Read a staged regular file without following a changed symlink."""
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(path, flags)
    if not stat.S_ISREG(os.fstat(descriptor).st_mode):
        os.close(descriptor)
        raise PackageError(f'staged path is no longer a regular file: {path}')
    return os.fdopen(descriptor, 'rb')


def _source_entries(source_root):
    usr = source_root / 'usr'
    if stat.S_ISLNK(os.lstat(usr).st_mode) or not usr.is_dir():
        raise PackageError('source tree must contain a real usr directory')
    entries = []
    total = 0

    def visit(path, relative):
        nonlocal total
        mode_info = os.lstat(path)
        mode = stat.S_IMODE(mode_info.st_mode)
        if mode & 0o7000:
            raise PackageError(f'setuid, setgid and sticky modes are forbidden: {relative}')
        _check_path(relative)
        if stat.S_ISDIR(mode_info.st_mode):
            entry = {'path': relative, 'type': 'dir', 'mode': mode}
            entries.append(entry)
            for child in sorted(os.scandir(path), key=lambda item: item.name):
                visit(Path(child.path), f'{relative}/{child.name}')
        elif stat.S_ISREG(mode_info.st_mode):
            size, digest = _hash_file(path)
            total += size
            if total > MAX_TOTAL:
                raise PackageError('package payload exceeds 4 GiB')
            entries.append({'path': relative, 'type': 'file', 'mode': mode,
                            'size': size, 'sha256': digest})
        elif stat.S_ISLNK(mode_info.st_mode):
            target = os.readlink(path)
            _check_link(relative, target)
            entries.append({'path': relative, 'type': 'symlink', 'target': target})
        else:
            raise PackageError(f'unsupported source file type: {relative}')
        if len(entries) > MAX_ENTRIES:
            raise PackageError('package contains too many entries')

    visit(usr, 'usr')
    return sorted(entries, key=lambda item: item['path'])


def _validate_manifest(manifest):
    if not isinstance(manifest, dict) or set(manifest) != {'format', 'package', 'files'}:
        raise PackageError('invalid manifest structure')
    if manifest['format'] != FORMAT:
        raise PackageError('unsupported system package format')
    package = manifest['package']
    if not isinstance(package, dict) or set(package) != {
            'name', 'version', 'arch', 'license', 'dependencies', 'source_sha256'}:
        raise PackageError('invalid package metadata')
    _validate_metadata(package['name'], package['version'], package['arch'],
                       package['license'], package['dependencies'], package['source_sha256'])
    files = manifest['files']
    if not isinstance(files, list) or not files or len(files) > MAX_ENTRIES:
        raise PackageError('invalid file list')
    paths = {}
    total = 0
    for entry in files:
        if not isinstance(entry, dict) or 'path' not in entry or 'type' not in entry:
            raise PackageError('invalid file entry')
        path = entry['path']
        _check_path(path)
        if path in paths:
            raise PackageError(f'duplicate package path: {path}')
        file_type = entry['type']
        if file_type == 'dir':
            expected = {'path', 'type', 'mode'}
        elif file_type == 'file':
            expected = {'path', 'type', 'mode', 'size', 'sha256'}
            if (not isinstance(entry.get('size'), int) or
                    isinstance(entry.get('size'), bool) or
                    not 0 <= entry['size'] <= MAX_FILE or
                    not isinstance(entry.get('sha256'), str) or
                    not SHA256.fullmatch(entry['sha256'])):
                raise PackageError(f'invalid file size or checksum: {path}')
            total += entry['size']
            if total > MAX_TOTAL:
                raise PackageError('package payload exceeds 4 GiB')
        elif file_type == 'symlink':
            expected = {'path', 'type', 'target'}
            _check_link(path, entry.get('target'))
        else:
            raise PackageError(f'unsupported file type: {file_type!r}')
        if set(entry) != expected:
            raise PackageError(f'invalid fields for {path}')
        if file_type != 'symlink' and (
                not isinstance(entry['mode'], int) or isinstance(entry['mode'], bool) or
                not 0 <= entry['mode'] <= 0o777):
            raise PackageError(f'unsafe mode for {path}')
        paths[path] = entry
    if [entry['path'] for entry in files] != sorted(paths):
        raise PackageError('manifest file list must be sorted')
    if paths.get('usr', {}).get('type') != 'dir':
        raise PackageError('package must include usr directory')
    for path in paths:
        parts = path.split('/')
        for count in range(2, len(parts)):
            if paths.get('/'.join(parts[:count]), {}).get('type') != 'dir':
                raise PackageError(f'missing or non-directory parent for {path}')
    return manifest


def build(source_root, output, name, version, arch, license_id,
          source_sha256, dependencies=(), epoch=0):
    """Create a reproducible archive from source_root/usr and return its path."""
    source_root, output = Path(source_root), Path(output)
    if source_root.is_symlink() or not source_root.is_dir():
        raise PackageError('source root must be a real directory')
    if output.resolve().is_relative_to(source_root.resolve()):
        raise PackageError('package output must be outside the source tree')
    if not isinstance(epoch, int) or not 0 <= epoch <= 0o77777777777:
        raise PackageError('invalid archive timestamp')
    deps = sorted(dependencies)
    _validate_metadata(name, version, arch, license_id, deps, source_sha256)
    manifest = _validate_manifest({
        'format': FORMAT,
        'package': {'name': name, 'version': version, 'arch': arch,
                    'license': license_id, 'dependencies': deps,
                    'source_sha256': source_sha256},
        'files': _source_entries(source_root),
    })
    body = _json_bytes(manifest)
    if len(body) > MAX_MANIFEST:
        raise PackageError('manifest exceeds 32 MiB')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile('wb', dir=output.parent,
                                         prefix=f'.{output.name}.', suffix='.tmp',
                                         delete=False) as raw:
            temporary = Path(raw.name)
            with tarfile.open(fileobj=raw, mode='w', format=tarfile.PAX_FORMAT) as archive:
                info = _tar_info('manifest.json', 0o644, epoch)
                info.size = len(body)
                archive.addfile(info, io.BytesIO(body))
                for entry in manifest['files']:
                    path = entry['path']
                    info = _tar_info(f'payload/{path}', entry.get('mode', 0o777), epoch)
                    if entry['type'] == 'dir':
                        info.type = tarfile.DIRTYPE
                        archive.addfile(info)
                    elif entry['type'] == 'symlink':
                        info.type = tarfile.SYMTYPE
                        info.linkname = entry['target']
                        archive.addfile(info)
                    else:
                        info.size = entry['size']
                        with _open_source(source_root / path) as content:
                            archive.addfile(info, content)
        verify(temporary)
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return output


def _tar_info(name, mode, epoch):
    info = tarfile.TarInfo(name)
    info.uid = info.gid = 0
    info.uname = info.gname = ''
    info.mtime = epoch
    info.mode = mode
    return info


def _read_archive(archive_path):
    """Read manifest and member index, checking every byte of every file."""
    try:
        with tarfile.open(archive_path, 'r:') as archive:
            members = []
            for member in archive:
                members.append(member)
                if len(members) > MAX_ENTRIES + 1:
                    raise PackageError('archive has too many members')
            if not members or len(members) > MAX_ENTRIES + 1:
                raise PackageError('invalid archive member count')
            first = members[0]
            if not first.isfile() or first.name != 'manifest.json' or first.size > MAX_MANIFEST:
                raise PackageError('archive must begin with manifest.json')
            content = archive.extractfile(first).read(MAX_MANIFEST + 1)
            try:
                manifest = json.loads(content.decode('utf-8'), object_pairs_hook=_unique_json)
            except (UnicodeError, json.JSONDecodeError) as error:
                raise PackageError(f'invalid manifest JSON: {error}') from error
            if _json_bytes(manifest) != content:
                raise PackageError('manifest is not canonical JSON')
            _validate_manifest(manifest)
            expected = manifest['files']
            if len(members) != len(expected) + 1:
                raise PackageError('archive member count differs from manifest')
            for member, entry in zip(members[1:], expected):
                path = entry['path']
                if member.name != f'payload/{path}':
                    raise PackageError(f'archive member mismatch: {member.name!r}')
                if (member.uid != 0 or member.gid != 0 or member.mtime < 0 or
                        member.mode != entry.get('mode', 0o777)):
                    raise PackageError(f'unsafe archive metadata: {path}')
                if entry['type'] == 'dir':
                    if not member.isdir() or member.size != 0:
                        raise PackageError(f'invalid directory member: {path}')
                elif entry['type'] == 'symlink':
                    if (not member.issym() or member.linkname != entry['target'] or
                            member.size != 0):
                        raise PackageError(f'invalid symlink member: {path}')
                else:
                    if not member.isfile() or member.size != entry['size']:
                        raise PackageError(f'invalid file member: {path}')
                    digest = hashlib.sha256()
                    with archive.extractfile(member) as source:
                        while block := source.read(1024 * 1024):
                            digest.update(block)
                    if digest.hexdigest() != entry['sha256']:
                        raise PackageError(f'file checksum mismatch: {path}')
            return manifest
    except (OSError, tarfile.TarError, EOFError) as error:
        raise PackageError(f'cannot read archive {archive_path}: {error}') from error


def verify(archive_path):
    """Return the validated NSPKG/1 manifest or raise PackageError."""
    return _read_archive(Path(archive_path))


def _lstat_optional(path):
    try:
        return os.lstat(path)
    except FileNotFoundError:
        return None


def _check_destination(root, entries):
    if root.is_symlink() or not root.is_dir():
        raise PackageError('rootfs target must be an existing real directory')
    for path, entry in entries.items():
        destination = root / path
        parents = list(destination.parents)
        for parent in reversed(parents[:-1]):
            if parent == root:
                continue
            if not parent.is_relative_to(root):
                continue
            status = _lstat_optional(parent)
            if status is not None and not stat.S_ISDIR(status.st_mode):
                raise PackageError(f'rootfs path has non-directory parent: {parent}')
        status = _lstat_optional(destination)
        if status is not None and (entry['type'] != 'dir' or
                                   not stat.S_ISDIR(status.st_mode)):
            raise PackageError(f'rootfs path already exists: {path}')


def _open_parent(root, path):
    flags = os.O_RDONLY | os.O_DIRECTORY | getattr(os, 'O_NOFOLLOW', 0)
    current = os.open(root, flags)
    try:
        for component in path.split('/')[:-1]:
            next_fd = os.open(component, flags, dir_fd=current)
            os.close(current)
            current = next_fd
        return current
    except Exception:
        os.close(current)
        raise


def _installed_package(root, name):
    """Read a recorded package without following rootfs or manifest symlinks."""
    path = f'usr/share/nekoos/system-packages/{name}.manifest'
    try:
        parent_fd = _open_parent(root, path)
    except FileNotFoundError:
        return None
    except OSError as error:
        raise PackageError(f'cannot read installed package {name}: {error}') from error
    try:
        try:
            flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0)
            fd = os.open(f'{name}.manifest', flags, dir_fd=parent_fd)
        except FileNotFoundError:
            return None
        with os.fdopen(fd, 'rb') as record:
            if not stat.S_ISREG(os.fstat(record.fileno()).st_mode):
                raise PackageError(f'installed package record is not a regular file: {name}')
            body = record.read(MAX_MANIFEST + 1)
    except OSError as error:
        raise PackageError(f'cannot read installed package {name}: {error}') from error
    finally:
        os.close(parent_fd)
    if len(body) > MAX_MANIFEST:
        raise PackageError(f'installed package record is too large: {name}')
    try:
        manifest = json.loads(body.decode('utf-8'), object_pairs_hook=_unique_json)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise PackageError(f'invalid installed package record for {name}: {error}') from error
    if _json_bytes(manifest) != body:
        raise PackageError(f'installed package record is not canonical JSON: {name}')
    _validate_manifest(manifest)
    package = manifest['package']
    if package['name'] != name:
        raise PackageError(f'installed package record names another package: {name}')
    return package


def _numeric_version(version):
    """Compare the dotted numeric release versions used by system recipes."""
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', version):
        raise PackageError(f'unsupported dependency version for comparison: {version!r}')
    return tuple(int(component) for component in version.split('.'))


def _version_at_least(actual, minimum):
    actual_parts = _numeric_version(actual)
    minimum_parts = _numeric_version(minimum)
    for current, required in zip_longest(actual_parts, minimum_parts, fillvalue=0):
        if current != required:
            return current > required
    return True


def _check_dependencies(root, packages):
    """Resolve dependencies before any rootfs writes occur."""
    if root.is_symlink() or not root.is_dir():
        raise PackageError('rootfs target must be an existing real directory')
    provided = {manifest['package']['name']: manifest['package']
                for _, manifest in packages}
    for package in provided.values():
        if package['arch'] != 'x86_64':
            raise PackageError(f"unsupported package architecture for {package['name']}: "
                               f"{package['arch']}; expected x86_64")
    installed = {}
    graph = {}
    for name, package in provided.items():
        graph[name] = set()
        for requirement in package['dependencies']:
            match = DEPENDENCY.fullmatch(requirement)
            dependency, minimum = match.groups()
            provider = provided.get(dependency)
            if provider is not None:
                graph[name].add(dependency)
            else:
                if dependency not in installed:
                    installed[dependency] = _installed_package(root, dependency)
                provider = installed[dependency]
            if provider is None:
                raise PackageError(f'missing dependency for {name}: {requirement}')
            if provider['arch'] != package['arch']:
                raise PackageError(f'wrong architecture for dependency {dependency}: '
                                   f"{provider['arch']}; expected {package['arch']}")
            if minimum is not None and not _version_at_least(provider['version'], minimum):
                raise PackageError(f'dependency {requirement} for {name} is too old: '
                                   f"found {provider['version']}")
    dependents = {name: set() for name in graph}
    for name, dependencies in graph.items():
        for dependency in dependencies:
            dependents[dependency].add(name)
    ready = sorted(name for name, dependencies in graph.items() if not dependencies)
    processed = 0
    while ready:
        name = ready.pop()
        processed += 1
        for dependent in sorted(dependents[name]):
            graph[dependent].remove(name)
            if not graph[dependent]:
                ready.append(dependent)
    if processed != len(graph):
        raise PackageError('cyclic package dependency')


def install(archive_paths, rootfs):
    """Preflight and install one or more archives into an existing rootfs.

    Files and links may not replace existing paths or each other. Existing
    directories can be shared. The function rolls back its own new paths on
    failure; callers should still use a disposable build rootfs.
    """
    root = Path(rootfs).absolute()
    packages = [(Path(path), verify(path)) for path in archive_paths]
    if not packages:
        raise PackageError('at least one package is required')
    combined = {}
    provenance = {}
    names = set()
    for _, manifest in packages:
        name = manifest['package']['name']
        if name in names:
            raise PackageError(f'duplicate package name: {name}')
        names.add(name)
        for entry in manifest['files']:
            path = entry['path']
            previous = combined.get(path)
            if previous is not None and not (entry['type'] == 'dir' and
                                              previous['type'] == 'dir'):
                raise PackageError(f'package path conflict: {path}')
            combined[path] = entry
        record_path = f'usr/share/nekoos/system-packages/{name}.manifest'
        provenance[record_path] = _json_bytes(manifest)
    _check_dependencies(root, packages)
    for directory in ('usr/share', 'usr/share/nekoos',
                      'usr/share/nekoos/system-packages'):
        previous = combined.get(directory)
        if previous is not None and previous['type'] != 'dir':
            raise PackageError(f'package path conflict: {directory}')
        combined.setdefault(directory, {'path': directory, 'type': 'dir', 'mode': 0o755})
    for path, body in provenance.items():
        if path in combined:
            raise PackageError(f'package path conflict: {path}')
        combined[path] = {'path': path, 'type': 'file', 'mode': 0o644,
                          'size': len(body), 'sha256': hashlib.sha256(body).hexdigest()}
    for path in combined:
        parts = path.split('/')
        for count in range(2, len(parts)):
            parent = '/'.join(parts[:count])
            if combined.get(parent, {}).get('type') != 'dir':
                raise PackageError(f'package path has non-directory parent: {path}')
    _check_destination(root, combined)
    created = []
    try:
        for path, entry in sorted(combined.items(), key=lambda item: (item[0].count('/'), item[0])):
            if entry['type'] != 'dir' or _lstat_optional(root / path) is not None:
                continue
            parent_fd = _open_parent(root, path)
            try:
                os.mkdir(path.split('/')[-1], 0o755, dir_fd=parent_fd)
                created.append((path, 'dir'))
            finally:
                os.close(parent_fd)
        for archive_path, manifest in packages:
            with tarfile.open(archive_path, 'r:') as archive:
                members = {}
                for member in archive:
                    if member.name in members or len(members) > MAX_ENTRIES:
                        raise PackageError('archive members changed during installation')
                    members[member.name] = member
                for entry in manifest['files']:
                    path = entry['path']
                    if entry['type'] == 'dir':
                        continue
                    parent_fd = _open_parent(root, path)
                    leaf = path.split('/')[-1]
                    try:
                        if entry['type'] == 'symlink':
                            os.symlink(entry['target'], leaf, dir_fd=parent_fd)
                            created.append((path, 'symlink'))
                        else:
                            flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
                            fd = os.open(leaf, flags, 0o600, dir_fd=parent_fd)
                            created.append((path, 'file'))
                            digest = hashlib.sha256()
                            with os.fdopen(fd, 'wb') as target, archive.extractfile(
                                    members[f'payload/{path}']) as source:
                                while block := source.read(1024 * 1024):
                                    target.write(block)
                                    digest.update(block)
                                target.flush()
                                os.fchmod(target.fileno(), entry['mode'])
                            if digest.hexdigest() != entry['sha256']:
                                raise PackageError(f'file changed during installation: {path}')
                    finally:
                        os.close(parent_fd)
        for path, body in provenance.items():
            parent_fd = _open_parent(root, path)
            try:
                flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
                fd = os.open(path.split('/')[-1], flags, 0o600, dir_fd=parent_fd)
                created.append((path, 'file'))
                with os.fdopen(fd, 'wb') as target:
                    target.write(body)
                    target.flush()
                    os.fchmod(target.fileno(), 0o644)
            finally:
                os.close(parent_fd)
        for path, kind in reversed(created):
            if kind != 'dir':
                continue
            parent_fd = _open_parent(root, path)
            try:
                os.chmod(path.split('/')[-1], combined[path]['mode'], dir_fd=parent_fd)
            finally:
                os.close(parent_fd)
    except Exception:
        for path, kind in reversed(created):
            try:
                parent_fd = _open_parent(root, path)
                try:
                    if kind == 'dir':
                        os.rmdir(path.split('/')[-1], dir_fd=parent_fd)
                    else:
                        os.unlink(path.split('/')[-1], dir_fd=parent_fd)
                finally:
                    os.close(parent_fd)
            except OSError:
                pass
        raise
    return [manifest for _, manifest in packages]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build_parser = commands.add_parser('build', help='create NSPKG/1 from a staged usr tree')
    build_parser.add_argument('--root', required=True, type=Path)
    build_parser.add_argument('--output', required=True, type=Path)
    build_parser.add_argument('--name', required=True)
    build_parser.add_argument('--version', required=True)
    build_parser.add_argument('--arch', default='x86_64')
    build_parser.add_argument('--license', required=True, dest='license_id')
    build_parser.add_argument('--source-sha256', required=True)
    build_parser.add_argument('--depends', action='append', default=[])
    verify_parser = commands.add_parser('verify', help='validate an NSPKG/1 archive')
    verify_parser.add_argument('archive', type=Path)
    install_parser = commands.add_parser('install', help='assemble packages into a rootfs')
    install_parser.add_argument('archives', nargs='+', type=Path)
    install_parser.add_argument('--root', required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == 'build':
            epoch = int(os.environ.get('SOURCE_DATE_EPOCH', '0'))
            build(args.root, args.output, args.name, args.version, args.arch,
                  args.license_id, args.source_sha256, args.depends, epoch)
            print(f'SYSTEM_PACKAGE_READY: {args.output}')
        elif args.command == 'verify':
            manifest = verify(args.archive)
            package = manifest['package']
            print(f"SYSTEM_PACKAGE_VERIFIED: {package['name']} {package['version']} ")
        else:
            manifests = install(args.archives, args.root)
            print('SYSTEM_PACKAGES_INSTALLED: ' + ', '.join(
                manifest['package']['name'] for manifest in manifests))
    except (OSError, PackageError, tarfile.TarError) as error:
        parser.error(str(error))
    return 0


if __name__ == '__main__':
    sys.exit(main())
