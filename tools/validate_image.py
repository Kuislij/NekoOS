#!/usr/bin/env python3
"""Check the cpio initramfs that will actually be passed to QEMU."""
import argparse
import gzip
import pathlib
import stat
import sys

MAX_UNPACKED_BYTES = 64 * 1024 * 1024
SOURCE_DATE_EPOCH = 1790035200


class InvalidImage(ValueError):
    pass


def require(condition, reason):
    if not condition:
        raise InvalidImage(reason)


def align4(offset):
    return (offset + 3) & ~3


def read_entries(image):
    with gzip.open(image, 'rb') as stream:
        data = stream.read(MAX_UNPACKED_BYTES + 1)
    require(len(data) <= MAX_UNPACKED_BYTES, 'initramfs is unexpectedly large')
    entries = {}
    offset = 0
    while True:
        require(offset + 110 <= len(data), 'truncated cpio header')
        header = data[offset:offset + 110]
        require(header[:6] in (b'070701', b'070702'), 'not a newc cpio archive')
        try:
            fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        except ValueError as error:
            raise InvalidImage('invalid cpio header field') from error
        mode, uid, gid, mtime, size = (
            fields[1], fields[2], fields[3], fields[5], fields[6]
        )
        device_major, device_minor, name_size = fields[9], fields[10], fields[11]
        offset += 110
        require(1 < name_size < 4096, 'invalid cpio filename length')
        require(offset + name_size <= len(data), 'truncated cpio filename')
        raw_name = data[offset:offset + name_size]
        require(raw_name.endswith(b'\0') and raw_name.count(b'\0') == 1,
                'invalid cpio filename')
        try:
            name = raw_name[:-1].decode('utf-8')
        except UnicodeDecodeError as error:
            raise InvalidImage('invalid UTF-8 cpio filename') from error
        offset = align4(offset + name_size)
        require(offset + size <= len(data), f'truncated cpio data for {name}')
        body = data[offset:offset + size]
        offset = align4(offset + size)
        if name == 'TRAILER!!!':
            require(size == 0, 'invalid cpio trailer')
            require(not any(data[offset:]), 'nonzero bytes after cpio trailer')
            return entries
        require(not name.startswith('/'), f'unsafe cpio path: {name}')
        path = '' if name == '.' else name.removeprefix('./')
        require(path == '' or all(part not in ('', '.', '..') for part in path.split('/')),
                f'unsafe cpio path: {name}')
        require(path not in entries, f'duplicate cpio path: {path}')
        require(uid == 0 and gid == 0, f'wrong owner: {path}')
        require(mtime == SOURCE_DATE_EPOCH, f'non-normalized timestamp: {path}')
        entries[path] = (mode, body, device_major, device_minor)


def validate(entries):
    def entry(path, predicate, kind):
        require(path in entries, f'missing {path}')
        item = entries[path]
        require(predicate(item[0]), f'{path} is not a {kind}')
        return item

    for directory in (
        '', 'dev', 'dev/pts', 'etc', 'home', 'media', 'mnt', 'opt', 'proc',
        'root', 'run', 'run/lock', 'state', 'sys', 'tmp', 'usr', 'usr/bin',
        'usr/include', 'usr/lib', 'usr/lib/tcc', 'usr/lib/tcc/include',
        'usr/lib64', 'usr/local', 'usr/local/bin', 'usr/local/lib',
        'usr/local/sbin', 'usr/sbin', 'usr/share', 'usr/share/nekoos',
        'usr/share/nekoos/examples', 'var', 'var/cache',
        'var/lib', 'var/log', 'var/tmp'
    ):
        entry(directory, stat.S_ISDIR, 'directory')
    for path, target in {
        'bin': b'usr/bin', 'sbin': b'usr/sbin', 'lib': b'usr/lib',
        'lib64': b'usr/lib64', 'var/run': b'../run',
        'var/lock': b'../run/lock', 'usr/bin/sh': b'busybox',
        'usr/bin/cc': b'tcc',
        'usr/lib/ld-musl-x86_64.so.1': b'/usr/lib/libc.so',
        'usr/sbin/init': b'../bin/busybox'
    }.items():
        require(entry(path, stat.S_ISLNK, 'symlink')[1] == target,
                f'wrong symlink target: {path}')
    for path in ('usr/bin/busybox', 'usr/bin/neko-help', 'usr/bin/neko-shell',
                 'usr/bin/tcc', 'usr/lib/libc.so', 'init'):
        mode = entry(path, stat.S_ISREG, 'regular file')[0]
        require(mode & 0o111, f'{path} is not executable')
    for path in ('etc/inittab', 'etc/os-release', 'etc/passwd', 'etc/group'):
        entry(path, stat.S_ISREG, 'regular file')
    for path in ('usr/share/nekoos/examples/hello.c', 'usr/include/stdio.h',
                 'usr/include/linux/version.h',
                 'usr/lib/libc.a', 'usr/lib/crt1.o', 'usr/lib/tcc/libtcc1.a'):
        entry(path, stat.S_ISREG, 'regular file')
    require(b'ID=nekoos' in entries['etc/os-release'][1], 'wrong os-release')
    require(b'ttyS0' in entries['etc/inittab'][1]
            and b'neko-shell' in entries['etc/inittab'][1],
            'serial shell missing')
    for path, major, minor in (('dev/console', 5, 1), ('dev/null', 1, 3)):
        mode, _, actual_major, actual_minor = entry(path, stat.S_ISCHR, 'device')
        require((actual_major, actual_minor) == (major, minor),
                f'wrong device number: {path}')
    for path in ('tmp', 'var/tmp'):
        require(entries[path][0] & 0o7777 == 0o1777, f'{path} must be sticky')
    require(entries['root'][0] & 0o7777 == 0o700,
            '/root must be private to root')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=pathlib.Path)
    args = parser.parse_args()
    try:
        entries = read_entries(args.image)
        validate(entries)
    except (OSError, EOFError, InvalidImage) as error:
        print(f'INITRAMFS_INVALID: {error}', file=sys.stderr)
        return 1
    print(f'INITRAMFS_VALID: {len(entries)} entries, merged /usr, permissions and devices')
    return 0


if __name__ == '__main__':
    sys.exit(main())
