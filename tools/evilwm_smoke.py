#!/usr/bin/env python3
"""Boot a disposable QEMU guest and verify the opt-in Xorg/evilwm session."""

import subprocess
import sys
import tempfile
from pathlib import Path

from boot_test import ROOT, run_disk_guest


GUEST_COMMAND = b'''if neko-x11-session --self-test; then
    poweroff
else
    printf '\nNEKO_X11_SESSION_FAILED\n'
    poweroff
fi
'''


def main():
    images = ROOT / 'out/images'
    if not (images / 'initramfs.cpio.gz').is_file():
        raise RuntimeError('build the NekoOS image first')
    with tempfile.TemporaryDirectory(prefix='evilwm-smoke-', dir=ROOT / 'build') as directory:
        state_disk = Path(directory) / 'state.img'
        subprocess.run(['qemu-img', 'create', '-f', 'raw', str(state_disk), '128M'],
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['mkfs.ext4', '-F', '-q', str(state_disk)],
                       check=True, stdout=subprocess.DEVNULL)
        run_disk_guest(images, state_disk, GUEST_COMMAND, 'NEKO_X11_SESSION_READY',
                       1, 120, False, log_prefix='evilwm-smoke', video=True)
    print('EVILWM_SMOKE_PASSED: NekoOS Xorg session managed a client window in QEMU')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'EVILWM_SMOKE_FAILED: {error}', file=sys.stderr)
        sys.exit(1)
