"""Check image integrity and preservation of an installed Arch VM."""

import hashlib
import io
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    'arch_vm', Path(__file__).resolve().parents[1] / 'tools/arch_vm.py')
arch_vm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(arch_vm)


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('qemu-img'),
                     'requires Linux and qemu-img')
class ArchVMTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix='neko-arch-guards-')
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.images = self.root / 'out/arch/images'
        self.images.mkdir(parents=True)
        for name in arch_vm.IMAGE_NAMES:
            (self.images / name).write_bytes(('artifact ' + name).encode())
        (self.images / 'system-template.img').write_bytes(b'original base' + bytes(1024 * 1024))
        (self.images / 'boot-mode.txt').write_bytes(b'grub\n')
        self.write_manifest()

    def write_manifest(self):
        (self.images / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.images / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in arch_vm.IMAGE_NAMES))

    def test_corrupted_kernel_is_refused_before_disk_creation(self):
        (self.images / 'vmlinuz-linux').write_bytes(b'corrupt')
        with self.assertRaisesRegex(RuntimeError, 'checksum verification failed'):
            arch_vm.verify_images(self.root)
        self.assertFalse((self.root / 'out/arch/disks').exists())

    def test_incomplete_duplicate_and_traversal_manifests_are_refused(self):
        manifest = self.images / 'SHA256SUMS'
        original = manifest.read_text()
        invalid = ((''.join(original.splitlines(keepends=True)[1:]), 'incomplete'),
                   (original + original.splitlines(keepends=True)[0], 'repeats'),
                   (original + '0' * 64 + '  ../outside.img\n', 'unsafe entry'))
        for content, reason in invalid:
            with self.subTest(reason=reason):
                manifest.write_text(content)
                with self.assertRaisesRegex(RuntimeError, reason):
                    arch_vm.verify_images(self.root)

    def test_symlinked_image_and_output_directory_are_refused(self):
        kernel = self.images / 'vmlinuz-linux'
        outside = self.root / 'external-kernel'
        kernel.rename(outside)
        kernel.symlink_to(outside)
        with self.assertRaisesRegex(RuntimeError, 'Unsafe file'):
            arch_vm.verify_images(self.root)
        kernel.unlink()
        outside.rename(kernel)
        real_images = self.images.with_name('external-images')
        self.images.rename(real_images)
        self.images.symlink_to(real_images, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, 'Unsafe directory'):
            arch_vm.verify_images(self.root)

    def test_rebuild_keeps_existing_disk_and_its_original_base(self):
        installed = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        disk, mode, _, _ = installed
        metadata = disk.with_name('system.json')
        old_metadata = metadata.read_bytes()
        old_disk = disk.read_bytes()
        record = json.loads(old_metadata)
        old_base = disk.parent / f'base-{record["base"]}.img'
        old_content = old_base.read_bytes()
        source = self.images / 'system-template.img'
        replacement = source.with_name('.replacement')
        replacement.write_bytes(b'new base' + bytes(1024 * 1024))
        replacement.replace(source)
        self.write_manifest()
        reloaded = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        self.assertEqual(reloaded, installed)
        self.assertEqual(mode, 'grub')
        self.assertEqual(disk.read_bytes(), old_disk)
        self.assertEqual(metadata.read_bytes(), old_metadata)
        self.assertEqual(old_base.read_bytes(), old_content)
        self.assertNotEqual(old_base.read_bytes(), source.read_bytes())

    def test_invalid_saved_metadata_preserves_disk(self):
        disk, _, _, _ = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        original = disk.read_bytes()
        disk.with_name('system.json').write_text('{"version":1,"base":"../outside","mode":"grub"}')
        with self.assertRaisesRegex(RuntimeError, 'Invalid persistent VM metadata'):
            arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        self.assertEqual(disk.read_bytes(), original)

    def test_changed_saved_base_is_refused_and_disk_is_preserved(self):
        disk, _, _, _ = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        original = disk.read_bytes()
        record = json.loads(disk.with_name('system.json').read_text())
        base = disk.parent / f'base-{record["base"]}.img'
        base.chmod(0o644)
        base.write_bytes(b'changed saved base')
        with self.assertRaisesRegex(RuntimeError, 'checksum failed'):
            arch_vm.prepare_persistent(self.root, (self.images, {}, 'grub'))
        self.assertEqual(disk.read_bytes(), original)

    def test_shared_vm_lock_excludes_builder(self):
        lock = self.root / 'build/arch/.build.lock'
        with arch_vm.file_lock(lock, shared=True):
            with arch_vm.file_lock(lock, shared=True):
                with self.assertRaisesRegex(RuntimeError, 'Another build or VM'):
                    with arch_vm.file_lock(lock):
                        self.fail('An exclusive builder lock entered while VMs held the image')

    def test_direct_disk_keeps_its_saved_kernel_when_new_image_becomes_grub(self):
        (self.images / 'boot-mode.txt').write_bytes(b'direct\n')
        self.write_manifest()
        installed = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        disk, mode, kernel, initramfs = installed
        self.assertEqual(mode, 'direct')
        saved_kernel, saved_initramfs = kernel.read_bytes(), initramfs.read_bytes()
        for name in ('system-template.img', 'vmlinuz-linux', 'initramfs-linux.img', 'boot-mode.txt'):
            replacement = self.images / ('.new-' + name)
            replacement.write_bytes(b'grub\n' if name == 'boot-mode.txt' else b'new artifact ' + name.encode())
            replacement.replace(self.images / name)
        self.write_manifest()
        self.assertEqual(arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root)), installed)
        self.assertEqual(kernel.read_bytes(), saved_kernel)
        self.assertEqual(initramfs.read_bytes(), saved_initramfs)
        command = arch_vm.qemu_command(disk, mode, kernel, initramfs, headless=True)
        self.assertEqual(command[command.index('-kernel') + 1], str(kernel))

    def test_changed_qcow_backing_is_refused_without_repairing_user_disk(self):
        disk, _, _, _ = arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        external = self.root / 'unexpected-base.img'
        external.write_bytes(bytes(1024 * 1024))
        subprocess.run(['qemu-img', 'rebase', '-u', '-f', 'qcow2', '-F', 'raw',
                        '-b', str(external), str(disk)], check=True)
        changed_disk = disk.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'unexpected backing file'):
            arch_vm.prepare_persistent(self.root, arch_vm.verify_images(self.root))
        self.assertEqual(disk.read_bytes(), changed_disk)

    def test_no_build_missing_images_never_invokes_a_builder_or_qemu(self):
        if os.geteuid() == 0:
            self.skipTest('CLI runs as a regular user')
        self.images.rename(self.images.with_name('saved-images'))
        with patch.object(arch_vm, 'ROOT', self.root), \
                patch.object(arch_vm.shutil, 'which', return_value='/fake/tool'), \
                patch.object(arch_vm.subprocess, 'run') as launch:
            with self.assertRaisesRegex(RuntimeError, 'images are missing'):
                arch_vm.main(['run', '--no-build', '--headless'])
        launch.assert_not_called()


class ArchVMCommandTests(unittest.TestCase):
    def test_grub_launch_boots_guest_disk_with_usb_input_without_external_kernel(self):
        command = arch_vm.qemu_command(Path('/tmp/system.qcow2'), 'grub', headless=True)
        for option in ('-kernel', '-initrd', '-append'):
            self.assertNotIn(option, command)
        self.assertIn('usb-kbd', command)
        self.assertIn('usb-tablet', command)
        self.assertNotIn('virtio-tablet-pci', command)
        self.assertNotIn('-no-reboot', command)

    def test_disposable_qa_exits_on_unexpected_guest_reboot(self):
        command = arch_vm.qemu_command(Path('/tmp/test-system.qcow2'), 'grub',
                                       headless=True, no_reboot=True)
        self.assertEqual(command.count('-no-reboot'), 1)

    def test_headless_run_preserves_interactive_stdio_and_creates_no_log(self):
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(arch_vm.subprocess, 'run') as launch:
            arch_vm.run_vm(['qemu-system-x86_64'], True, Path(directory))
            launch.assert_called_once_with(['qemu-system-x86_64'], check=True)
            self.assertFalse((Path(directory) / 'build').exists())


class ArchVMMarkerTests(unittest.TestCase):
    def guest_with_log(self, content):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        log = Path(directory.name) / 'guest.log'
        log.write_text(content, encoding='utf-8')
        guest = arch_vm.Guest([], log)
        guest.process = Mock()
        guest.process.poll.return_value = 0
        guest.deadline = time.monotonic() + 1
        return guest

    def test_osc_and_dcs_annotations_and_csi_colours_do_not_hide_ready_marker(self):
        for introducer in (']3008;start=login', 'Pconsole-context'):
            for terminator in ('\x1b\\', '\x07'):
                with self.subTest(introducer=introducer, terminator=repr(terminator)):
                    content = (f'\x1b{introducer}{terminator}\x1b[32mNEKO_ARCH_READY'
                               '\x1b[0m\r\n')
                    guest = self.guest_with_log(content)
                    guest.wait('NEKO_ARCH_READY')
                    guest.process.poll.assert_not_called()
                    self.assertIn('\x1b', guest.log.read_text())

    def test_annotated_failure_marker_is_still_a_failure(self):
        guest = self.guest_with_log('\x1b]3008;start=check\x07ARCH_GUEST_FAILED'
                                    '\x1b]3008;end=check\x1b\\\n')
        with self.assertRaisesRegex(RuntimeError, 'assertion failed'):
            guest.wait('NEKO_ARCH_READY')

    def test_echoed_split_marker_command_cannot_claim_guest_readiness(self):
        content = '\x1b]3008;start=command\x1b\\neko$ ' + arch_vm.marker_command('NEKO_ARCH_READY') + '\r\n'
        guest = self.guest_with_log(content)
        with self.assertRaisesRegex(RuntimeError, 'exited before NEKO_ARCH_READY'):
            guest.wait('NEKO_ARCH_READY')
        guest.process.poll.assert_called_once()


@unittest.skipUnless(sys.platform == 'linux' and shutil.which('bash'), 'requires Bash')
class ArchVMShellReadinessTests(unittest.TestCase):
    def test_visible_shell_rejects_normal_dialog_offscreen_and_hidden_windows(self):
        fixture = r'''
xdotool() {
    case "$1" in
        search) test "$VISIBLE" = yes || return 1; printf '51\n' ;;
        getwindowgeometry) printf 'X=0\nY=%s\nWIDTH=1280\nHEIGHT=26\n' "$WINDOW_Y" ;;
    esac
}
xprop() { printf '_NET_WM_WINDOW_TYPE(ATOM) = _NET_WM_WINDOW_TYPE_%s\n' "$WINDOW_TYPE"; }
screen_width=1280 screen_height=800
mapped_shell_window '[Xx]fce4-panel' DOCK 640 16
'''
        cases = (('DOCK', '0', 'yes', True), ('NORMAL', '0', 'yes', False),
                 ('DOCK', '900', 'yes', False), ('DOCK', '0', 'no', False))
        for kind, y, visible, expected in cases:
            with self.subTest(kind=kind, y=y, visible=visible):
                environment = dict(os.environ, WINDOW_TYPE=kind, WINDOW_Y=y, VISIBLE=visible)
                result = subprocess.run(['bash', '-c', arch_vm.GUEST_HELPERS + fixture],
                                        env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(result.returncode == 0, expected, result.stderr)

    def test_failed_assertion_remains_failure_even_if_diagnostics_fail(self):
        guest = arch_vm.Guest([], Path('/unused-log'))
        guest.process = Mock()
        guest.process.stdin = io.BytesIO()
        guest.wait = Mock()
        guest.check('arch_guest_diagnostics() { printf "fixture diagnostics\\n"; false; }\nfalse',
                    'NEKO_ARCH_DESKTOP_READY')
        command = guest.process.stdin.getvalue().decode()
        result = subprocess.run(['bash', '-c', command], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        lines = arch_vm.terminal_text(result.stdout).splitlines()
        self.assertIn('ARCH_GUEST_FAILED', lines)
        self.assertIn('fixture diagnostics', lines)
        self.assertNotIn('NEKO_ARCH_DESKTOP_READY', lines)


@unittest.skipUnless(sys.platform == 'linux', 'requires Linux file guards')
class ArchVMLogTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix='neko-arch-log-')
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.log = self.root / 'build/logs/arch-run.log'
        self.log.parent.mkdir(parents=True)

    def test_graphical_run_logs_serial_and_errors_with_closed_terminal_input(self):
        command = [sys.executable, '-c',
                   'import sys; print("serial boot output"); '
                   'print("QEMU diagnostic", file=sys.stderr); '
                   'print("INPUT_EOF=" + str(sys.stdin.read() == ""))']
        arch_vm.run_vm(command, False, self.root)
        output = self.log.read_text()
        self.assertIn('serial boot output', output)
        self.assertIn('QEMU diagnostic', output)
        self.assertIn('INPUT_EOF=True', output)

    def test_symlink_and_hardlink_log_guards_preserve_external_file_before_launch(self):
        external = self.root / 'user-file'
        external.write_bytes(b'preserved user data')
        for hardlink in (False, True):
            with self.subTest(hardlink=hardlink):
                if hardlink:
                    os.link(external, self.log)
                else:
                    self.log.symlink_to(external)
                with patch.object(arch_vm.subprocess, 'run') as launch:
                    with self.assertRaisesRegex(RuntimeError, 'Unsafe file'):
                        arch_vm.run_vm(['qemu-system-x86_64'], False, self.root)
                launch.assert_not_called()
                self.assertEqual(external.read_bytes(), b'preserved user data')
                self.log.unlink()

    def test_guest_timeout_reaps_the_real_child_and_preserves_its_log(self):
        command = [sys.executable, '-c', 'import time; print("boot stalled", flush=True); time.sleep(30)']
        with self.assertRaisesRegex(RuntimeError, 'Timed out'):
            with arch_vm.Guest(command, self.log, timeout=0.1) as guest:
                process = guest.process
                guest.wait('NEKO_ARCH_READY')
        self.assertIsNotNone(process.poll())
        self.assertIn('boot stalled', self.log.read_text())


if __name__ == '__main__':
    unittest.main()
