#!/usr/bin/env python3
"""Check the cpio initramfs that will actually be passed to QEMU."""
import argparse
import gzip
import pathlib
import stat
import sys

# The graphical SDK includes headers, GIO tools, and multiple shared libraries.
MAX_UNPACKED_BYTES = 128 * 1024 * 1024
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
        '', 'dev', 'dev/pts', 'etc', 'etc/neko', 'etc/neko/services',
        'home', 'media', 'mnt', 'opt', 'proc',
        'root', 'run', 'run/lock', 'state', 'sys', 'tmp', 'usr', 'usr/bin',
        'usr/include', 'usr/lib', 'usr/lib/tcc', 'usr/lib/tcc/include',
        'usr/include/pixman-1', 'usr/lib/pkgconfig',
        'usr/include/glib-2.0', 'usr/include/glib-2.0/gio',
        'usr/include/xfce4', 'usr/include/xfce4/libxfce4util',
        'usr/include/freetype2', 'usr/include/freetype2/freetype',
        'usr/include/libpng16',
        'usr/include/cairo',
        'usr/include/fontconfig', 'usr/include/dbus-1.0',
        'usr/include/dbus-1.0/dbus',
        'usr/lib/dbus-1.0', 'usr/lib/dbus-1.0/include',
        'usr/lib/dbus-1.0/include/dbus',
        'usr/etc', 'usr/etc/fonts', 'usr/etc/fonts/conf.d',
        'usr/lib/glib-2.0', 'usr/lib/glib-2.0/include',
        'usr/include/X11', 'usr/include/X11/extensions',
        'usr/include/X11/Xtrans', 'usr/include/GL',
        'usr/include/xcb',
        'usr/include/libdrm', 'usr/include/libxcvt', 'usr/include/X11/fonts',
        'usr/include/xorg',
        'usr/lib64', 'usr/local', 'usr/local/bin', 'usr/local/etc',
        'usr/local/etc/neko', 'usr/local/etc/neko/services', 'usr/local/lib',
        'usr/local/sbin', 'usr/sbin', 'usr/share', 'usr/share/nekoos',
        'usr/share/nekoos/examples', 'usr/share/nekoos/packages', 'var', 'var/cache',
        'usr/share/nekoos/system-packages', 'usr/share/licenses',
        'usr/share/licenses/pixman',
        'usr/share/licenses/xorgproto', 'usr/share/licenses/libxau',
        'usr/share/licenses/libxdmcp', 'usr/share/pkgconfig',
        'usr/share/licenses/libxcb', 'usr/share/licenses/xtrans',
        'usr/share/licenses/libx11', 'usr/share/licenses/libxext',
        'usr/share/licenses/libxrender',
        'usr/share/licenses/libxfixes',
        'usr/share/licenses/libxrandr',
        'usr/share/licenses/evilwm', 'usr/share/licenses/libffi',
        'usr/share/licenses/pcre2',
        'usr/share/licenses/libpng',
        'usr/share/licenses/expat',
        'usr/share/licenses/freetype',
        'usr/share/licenses/fontconfig', 'usr/share/licenses/dbus',
        'usr/share/licenses/dejavu-fonts',
        'usr/share/licenses/cairo',
        'usr/share/dbus-1',
        'usr/share/licenses/glib',
        'usr/share/licenses/libxfce4util',
        'usr/share/licenses/zlib', 'usr/share/licenses/libxkbfile',
        'usr/share/licenses/xkbcomp', 'usr/share/licenses/xkeyboard-config',
        'usr/share/licenses/libfontenc', 'usr/share/licenses/libxfont2',
        'usr/share/licenses/font-misc-misc', 'usr/share/licenses/libxcvt',
        'usr/share/licenses/libpciaccess', 'usr/share/licenses/libdrm',
        'usr/share/licenses/libsha1',
        'usr/share/licenses/xorg-server',
        'usr/share/licenses/libevdev', 'usr/share/licenses/mtdev',
        'usr/share/licenses/xf86-input-evdev',
        'usr/share/X11', 'usr/share/X11/locale', 'usr/share/aclocal',
        'usr/share/xkeyboard-config-2', 'usr/share/fonts',
        'usr/share/fonts/X11', 'usr/share/fonts/X11/misc',
        'usr/share/fonts/truetype', 'usr/share/fonts/truetype/dejavu',
        'usr/lib/xorg', 'usr/lib/xorg/modules',
        'usr/lib/xorg/modules/drivers', 'usr/share/X11/xorg.conf.d',
        'usr/lib/xorg/modules/input',
        'var/lib', 'var/lib/neko-services', 'var/lib/neko-services/enabled',
        'var/lib/neko-services/disabled', 'var/log', 'var/tmp'
    ):
        entry(directory, stat.S_ISDIR, 'directory')
    for path, target in {
        'bin': b'usr/bin', 'sbin': b'usr/sbin', 'lib': b'usr/lib',
        'lib64': b'usr/lib64', 'var/run': b'../run',
        'var/lock': b'../run/lock', 'usr/bin/sh': b'busybox',
        'usr/bin/cc': b'tcc',
        'usr/lib/ld-musl-x86_64.so.1': b'/usr/lib/libc.so',
        'usr/lib/libpixman-1.so': b'libpixman-1.so.0',
        'usr/lib/libXau.so.6': b'libXau.so.6.0.0',
        'usr/lib/libXdmcp.so.6': b'libXdmcp.so.6.0.0',
        'usr/lib/libxcb.so.1': b'libxcb.so.1.1.0',
        'usr/lib/libX11.so.6': b'libX11.so.6.4.0',
        'usr/lib/libX11-xcb.so.1': b'libX11-xcb.so.1.0.0',
        'usr/lib/libXext.so.6': b'libXext.so.6.4.0',
        'usr/lib/libXrender.so.1': b'libXrender.so.1.3.0',
        'usr/lib/libXfixes.so.3': b'libXfixes.so.3.1.0',
        'usr/lib/libXrandr.so.2': b'libXrandr.so.2.2.0',
        'usr/lib/libffi.so.8': b'libffi.so.8.2.0',
        'usr/lib/libpng16.so.16': b'libpng16.so.16.58.0',
        'usr/include/png.h': b'libpng16/png.h',
        'usr/include/pngconf.h': b'libpng16/pngconf.h',
        'usr/lib/libpcre2-8.so.0': b'libpcre2-8.so.0.16.0',
        'usr/lib/libpcre2-16.so.0': b'libpcre2-16.so.0.16.0',
        'usr/lib/libpcre2-32.so.0': b'libpcre2-32.so.0.16.0',
        'usr/lib/libpcre2-posix.so.3': b'libpcre2-posix.so.3.0.8',
        'usr/lib/libexpat.so.1': b'libexpat.so.1.12.5',
        'usr/lib/libfreetype.so.6': b'libfreetype.so.6.20.6',
        'usr/lib/libfontconfig.so.1': b'libfontconfig.so.1.16.0',
        'usr/lib/libdbus-1.so.3': b'libdbus-1.so.3.38.3',
        'usr/lib/libcairo.so.2': b'libcairo.so.2.11806.6',
        'usr/lib/libcairo-gobject.so.2': b'libcairo-gobject.so.2.11806.6',
        'usr/lib/libglib-2.0.so.0': b'libglib-2.0.so.0.8400.4',
        'usr/lib/libgobject-2.0.so.0': b'libgobject-2.0.so.0.8400.4',
        'usr/lib/libgio-2.0.so.0': b'libgio-2.0.so.0.8400.4',
        'usr/lib/libxfce4util.so.7': b'libxfce4util.so.7.0.0',
        'usr/lib/libz.so.1': b'libz.so.1.3.2',
        'usr/lib/libxkbfile.so.1': b'libxkbfile.so.1.0.2',
        'usr/lib/libfontenc.so.1': b'libfontenc.so.1.0.0',
        'usr/lib/libXfont2.so.2': b'libXfont2.so.2.0.0',
        'usr/lib/libxcvt.so.0': b'libxcvt.so.0.1.3',
        'usr/lib/libpciaccess.so.0': b'libpciaccess.so.0.11.1',
        'usr/lib/libdrm.so.2': b'libdrm.so.2.134.0',
        'usr/lib/libsha1.so.0': b'libsha1.so.0.0.0',
        'usr/lib/libevdev.so.2': b'libevdev.so.2.3.0',
        'usr/lib/libmtdev.so.1': b'libmtdev.so.1.0.0',
        'usr/share/X11/xkb': b'../xkeyboard-config-2',
        'usr/bin/X': b'Xorg',
        'usr/sbin/init': b'../bin/busybox'
    }.items():
        require(entry(path, stat.S_ISLNK, 'symlink')[1] == target,
                f'wrong symlink target: {path}')
    for path in ('usr/bin/busybox', 'usr/bin/neko-help', 'usr/bin/neko-shell',
                 'usr/bin/neko-session', 'usr/bin/neko-desktop',
                 'usr/bin/neko-pkg',
                 'usr/bin/neko-service', 'etc/neko/services/network',
                 'usr/bin/neko-pixman-check',
                 'usr/bin/neko-x11-base-check',
                 'usr/bin/neko-xcb-check',
                 'usr/bin/neko-xlib-check', 'usr/bin/neko-xext-check',
                 'usr/bin/neko-xorg-stack-check', 'usr/bin/xkbcomp',
                 'usr/bin/neko-xorg-window-check',
                 'usr/bin/neko-x11-extensions-check',
                 'usr/bin/neko-x11-welcome',
                 'usr/bin/neko-x11-session', 'usr/bin/neko-evilwm-check',
                 'usr/bin/neko-libffi-check',
                 'usr/bin/neko-libpng-check',
                 'usr/bin/neko-pcre2-check',
                 'usr/bin/neko-expat-check',
                 'usr/bin/neko-freetype-check',
                 'usr/bin/neko-fontconfig-check',
                 'usr/bin/neko-glib-check',
                 'usr/bin/neko-cairo-check',
                 'usr/bin/neko-libxfce4util-check',
                 'usr/bin/pcre2-config',
                 'usr/bin/gio', 'usr/bin/gdbus',
                 'usr/bin/glib-compile-schemas',
                 'usr/sbin/xfce4-kiosk-query',
                 'usr/bin/fc-match', 'usr/bin/fc-list', 'usr/bin/fc-cache',
                 'usr/bin/dbus-daemon', 'usr/bin/dbus-run-session',
                 'usr/bin/evilwm',
                 'usr/bin/cvt',
                 'usr/bin/Xorg', 'usr/bin/gtf',
                 'usr/lib/xorg/modules/drivers/modesetting_drv.so',
                 'usr/lib/xorg/modules/input/evdev_drv.so',
                 'usr/bin/mtdev-test',
                 'etc/neko/services/desktop',
                 'usr/bin/tcc', 'usr/lib/libc.so', 'init', 'neko-update'):
        mode = entry(path, stat.S_ISREG, 'regular file')[0]
        require(mode & 0o111, f'{path} is not executable')
    for path in ('etc/inittab', 'etc/os-release', 'etc/passwd', 'etc/group',
                 'etc/neko/boot-services', 'usr/share/nekoos/etc-baseline.sha256'):
        entry(path, stat.S_ISREG, 'regular file')
    for path in ('usr/share/nekoos/examples/hello.c',
                 'usr/share/nekoos/packages/neko-greet-0.1.0.npkg',
                 'usr/share/nekoos/packages/neko-greet-0.2.0.npkg',
                 'usr/share/nekoos/packages/neko-greet-0.3.0.npkg',
                 'usr/share/nekoos/packages/neko-companion-1.0.0.npkg',
                 'usr/share/nekoos/packages/neko-theme-1.0.0.npkg',
                 'usr/share/nekoos/packages/neko-theme-1.1.0.npkg',
                 'usr/include/stdio.h',
                 'usr/include/pixman-1/pixman.h',
                 'usr/lib/pkgconfig/pixman-1.pc',
                 'usr/share/licenses/pixman/COPYING',
                 'usr/share/nekoos/system-packages/pixman.manifest',
                 'usr/lib/libpixman-1.so.0.46.4',
                 'usr/include/X11/X.h', 'usr/include/X11/Xauth.h',
                 'usr/include/X11/Xdmcp.h', 'usr/share/pkgconfig/xproto.pc',
                 'usr/lib/pkgconfig/xau.pc', 'usr/lib/pkgconfig/xdmcp.pc',
                 'usr/lib/libXau.so.6.0.0', 'usr/lib/libXdmcp.so.6.0.0',
                 'usr/share/licenses/libxau/COPYING',
                 'usr/share/licenses/libxdmcp/COPYING',
                 'usr/share/licenses/xorgproto/COPYING-glproto',
                 'usr/share/nekoos/system-packages/xorgproto.manifest',
                 'usr/share/nekoos/system-packages/libxau.manifest',
                 'usr/share/nekoos/system-packages/libxdmcp.manifest',
                 'usr/include/xcb/xcb.h', 'usr/lib/pkgconfig/xcb.pc',
                 'usr/lib/libxcb.so.1.1.0',
                 'usr/share/licenses/libxcb/COPYING',
                 'usr/share/nekoos/system-packages/libxcb.manifest',
                 'usr/include/X11/Xtrans/Xtrans.h',
                 'usr/share/pkgconfig/xtrans.pc',
                 'usr/share/licenses/xtrans/COPYING',
                 'usr/share/nekoos/system-packages/xtrans.manifest',
                 'usr/include/X11/Xlib.h', 'usr/lib/pkgconfig/x11.pc',
                 'usr/lib/libX11.so.6.4.0', 'usr/lib/libX11-xcb.so.1.0.0',
                 'usr/share/licenses/libx11/COPYING',
                 'usr/share/nekoos/system-packages/libx11.manifest',
                 'usr/include/X11/extensions/Xext.h',
                 'usr/lib/pkgconfig/xext.pc', 'usr/lib/libXext.so.6.4.0',
                 'usr/share/licenses/libxext/COPYING',
                 'usr/share/nekoos/system-packages/libxext.manifest',
                 'usr/include/X11/extensions/Xrender.h',
                 'usr/lib/pkgconfig/xrender.pc',
                 'usr/lib/libXrender.so.1.3.0',
                 'usr/share/nekoos/system-packages/libxrender.manifest',
                 'usr/include/X11/extensions/Xfixes.h',
                 'usr/lib/pkgconfig/xfixes.pc',
                 'usr/lib/libXfixes.so.3.1.0',
                 'usr/share/nekoos/system-packages/libxfixes.manifest',
                 'usr/include/X11/extensions/Xrandr.h',
                 'usr/lib/pkgconfig/xrandr.pc',
                 'usr/lib/libXrandr.so.2.2.0',
                 'usr/share/nekoos/system-packages/libxrandr.manifest',
                 'usr/share/nekoos/system-packages/evilwm.manifest',
                 'usr/share/licenses/evilwm/README',
                 'usr/include/ffi.h', 'usr/include/ffitarget.h',
                 'usr/lib/pkgconfig/libffi.pc', 'usr/lib/libffi.so.8.2.0',
                 'usr/share/licenses/libffi/LICENSE',
                 'usr/share/nekoos/system-packages/libffi.manifest',
                 'usr/include/libpng16/png.h',
                 'usr/include/libpng16/pngconf.h',
                 'usr/lib/pkgconfig/libpng16.pc',
                 'usr/lib/libpng16.so.16.58.0',
                 'usr/share/licenses/libpng/LICENSE',
                 'usr/share/nekoos/system-packages/libpng.manifest',
                 'usr/include/pcre2.h', 'usr/include/pcre2posix.h',
                 'usr/lib/pkgconfig/libpcre2-8.pc',
                 'usr/lib/pkgconfig/libpcre2-16.pc',
                 'usr/lib/pkgconfig/libpcre2-32.pc',
                 'usr/lib/pkgconfig/libpcre2-posix.pc',
                 'usr/lib/libpcre2-8.so.0.16.0',
                 'usr/lib/libpcre2-16.so.0.16.0',
                 'usr/lib/libpcre2-32.so.0.16.0',
                 'usr/lib/libpcre2-posix.so.3.0.8',
                 'usr/share/licenses/pcre2/LICENCE.md',
                 'usr/share/nekoos/system-packages/pcre2.manifest',
                 'usr/include/expat.h', 'usr/include/expat_external.h',
                 'usr/lib/pkgconfig/expat.pc',
                 'usr/lib/libexpat.so.1.12.5',
                 'usr/share/licenses/expat/COPYING',
                 'usr/share/nekoos/system-packages/expat.manifest',
                 'usr/include/freetype2/ft2build.h',
                 'usr/include/freetype2/freetype/freetype.h',
                 'usr/lib/pkgconfig/freetype2.pc',
                 'usr/lib/libfreetype.so.6.20.6',
                 'usr/share/licenses/freetype/LICENSE.TXT',
                 'usr/share/licenses/freetype/FTL.TXT',
                 'usr/share/nekoos/system-packages/freetype.manifest',
                 'usr/include/fontconfig/fontconfig.h',
                 'usr/lib/pkgconfig/fontconfig.pc',
                 'usr/lib/libfontconfig.so.1.16.0',
                 'usr/etc/fonts/fonts.conf',
                 'usr/share/licenses/fontconfig/COPYING',
                 'usr/share/nekoos/system-packages/fontconfig.manifest',
                 'usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                 'usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
                 'usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf',
                 'usr/share/licenses/dejavu-fonts/LICENSE',
                 'usr/share/nekoos/system-packages/dejavu-fonts.manifest',
                 'usr/include/dbus-1.0/dbus/dbus.h',
                 'usr/lib/dbus-1.0/include/dbus/dbus-arch-deps.h',
                 'usr/lib/pkgconfig/dbus-1.pc',
                 'usr/lib/libdbus-1.so.3.38.3',
                 'usr/share/dbus-1/session.conf',
                 'usr/share/licenses/dbus/COPYING',
                 'usr/share/nekoos/system-packages/dbus.manifest',
                 'usr/include/glib-2.0/glib.h',
                 'usr/include/glib-2.0/glib-object.h',
                 'usr/include/glib-2.0/gio/gio.h',
                 'usr/lib/glib-2.0/include/glibconfig.h',
                 'usr/lib/pkgconfig/glib-2.0.pc',
                 'usr/lib/pkgconfig/gobject-2.0.pc',
                 'usr/lib/pkgconfig/gio-2.0.pc',
                 'usr/lib/libglib-2.0.so.0.8400.4',
                 'usr/lib/libgobject-2.0.so.0.8400.4',
                 'usr/lib/libgio-2.0.so.0.8400.4',
                 'usr/share/licenses/glib/COPYING',
                 'usr/share/nekoos/system-packages/glib.manifest',
                 'usr/include/xfce4/libxfce4util/libxfce4util.h',
                 'usr/lib/pkgconfig/libxfce4util-1.0.pc',
                 'usr/lib/libxfce4util.so.7.0.0',
                 'usr/share/licenses/libxfce4util/COPYING',
                 'usr/share/nekoos/system-packages/libxfce4util.manifest',
                 'usr/include/cairo/cairo.h',
                 'usr/include/cairo/cairo-ft.h',
                 'usr/include/cairo/cairo-xlib.h',
                 'usr/include/cairo/cairo-xcb.h',
                 'usr/lib/pkgconfig/cairo.pc',
                 'usr/lib/pkgconfig/cairo-png.pc',
                 'usr/lib/pkgconfig/cairo-ft.pc',
                 'usr/lib/pkgconfig/cairo-xlib.pc',
                 'usr/lib/pkgconfig/cairo-xcb.pc',
                 'usr/lib/pkgconfig/cairo-gobject.pc',
                 'usr/lib/libcairo.so.2.11806.6',
                 'usr/lib/libcairo-gobject.so.2.11806.6',
                 'usr/share/licenses/cairo/COPYING',
                 'usr/share/nekoos/system-packages/cairo.manifest',
                 'usr/include/zlib.h', 'usr/lib/libz.so.1.3.2',
                 'usr/share/licenses/zlib/LICENSE',
                 'usr/share/nekoos/system-packages/zlib.manifest',
                 'usr/include/X11/extensions/XKBfile.h',
                 'usr/lib/libxkbfile.so.1.0.2',
                 'usr/share/nekoos/system-packages/libxkbfile.manifest',
                 'usr/share/nekoos/system-packages/xkbcomp.manifest',
                 'usr/share/nekoos/system-packages/xkeyboard-config.manifest',
                 'usr/share/xkeyboard-config-2/rules/evdev',
                 'usr/share/xkeyboard-config-2/symbols/us',
                 'usr/share/xkeyboard-config-2/symbols/ru',
                 'usr/lib/libfontenc.so.1.0.0',
                 'usr/lib/libXfont2.so.2.0.0',
                 'usr/share/fonts/X11/misc/fonts.dir',
                 'usr/share/fonts/X11/misc/fonts.alias',
                 'usr/share/fonts/X11/misc/6x13.pcf',
                 'usr/share/fonts/X11/misc/9x15.pcf',
                 'usr/share/nekoos/system-packages/font-misc-misc.manifest',
                 'usr/lib/libxcvt.so.0.1.3',
                 'usr/lib/libpciaccess.so.0.11.1',
                 'usr/lib/libdrm.so.2.134.0',
                 'usr/share/nekoos/system-packages/libdrm.manifest',
                 'usr/lib/libsha1.so.0.0.0',
                 'usr/share/nekoos/system-packages/libsha1.manifest',
                 'usr/share/licenses/xorg-server/COPYING',
                 'usr/share/nekoos/system-packages/xorg-server.manifest',
                 'usr/lib/libevdev.so.2.3.0',
                 'usr/lib/libmtdev.so.1.0.0',
                 'usr/share/nekoos/system-packages/libevdev.manifest',
                 'usr/share/nekoos/system-packages/mtdev.manifest',
                 'usr/share/nekoos/system-packages/xf86-input-evdev.manifest',
                 'usr/include/linux/version.h',
                 'usr/lib/libc.a', 'usr/lib/crt1.o', 'usr/lib/tcc/libtcc1.a'):
        entry(path, stat.S_ISREG, 'regular file')
    for name in ('6x13.pcf', '9x15.pcf'):
        path = f'usr/share/fonts/X11/misc/{name}'
        require(entries[path][1].startswith(b'\x01fcp'),
                f'{path} is not a compiled PCF font')
    require(b'ID=nekoos' in entries['etc/os-release'][1], 'wrong os-release')
    require(b'neko:x:1000:1000:' in entries['etc/passwd'][1]
            and b'neko:x:1000:' in entries['etc/group'][1],
            'desktop user or group missing')
    require(b'desktop' in entries['etc/neko/boot-services'][1],
            'desktop service missing from boot manifest')
    require(b'::sysinit:/usr/bin/neko-service boot' in entries['etc/inittab'][1]
            and b'ttyS0' in entries['etc/inittab'][1]
            and b'neko-shell' in entries['etc/inittab'][1],
            'boot services or serial shell missing')
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
