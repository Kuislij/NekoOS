"""Failure-path checks for the VM test harness; no guest image required."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from threading import Thread
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'boot_test', Path(__file__).resolve().parents[1] / 'tools/boot_test.py'
)
boot_test = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot_test)


@unittest.skipUnless(sys.platform == 'linux', 'requires Linux sha256sum')
class BootHarnessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.images = self.root / 'out/images'
        self.images.mkdir(parents=True)
        lines = []
        for name in ('bzImage', 'initramfs.cpio.gz'):
            data = b'test fixture'
            (self.images / name).write_bytes(data)
            lines.append(f'{hashlib.sha256(data).hexdigest()}  {name}\n')
        (self.images / 'SHA256SUMS').write_text(''.join(lines))
        self.root_patch = patch.object(boot_test, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_corrupt_image_is_rejected_before_launch(self):
        (self.images / 'bzImage').write_bytes(b'corrupted')
        with self.assertRaises(subprocess.CalledProcessError):
            boot_test.boot(argparse.Namespace(no_build=True, timeout=1))
        self.assertFalse((self.root / 'build/logs/boot-test.log').exists())

    def test_timeout_reaps_the_child_process(self):
        original_popen = subprocess.Popen
        original_run = subprocess.run
        children = []

        def launch(command, **kwargs):
            if command[0] == 'qemu-system-x86_64':
                command = [sys.executable, '-c', 'import time; time.sleep(30)']
                child = original_popen(command, **kwargs)
                children.append(child)
                return child
            return original_popen(command, **kwargs)

        def run(command, **kwargs):
            if command[0] == sys.executable:
                return subprocess.CompletedProcess(command, 0)
            return original_run(command, **kwargs)

        with patch.object(boot_test.subprocess, 'Popen', side_effect=launch), \
             patch.object(boot_test.subprocess, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'did not complete'):
                boot_test.boot(argparse.Namespace(no_build=True, timeout=0.2))
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())


@unittest.skipUnless(sys.platform == 'linux', 'requires UNIX domain sockets')
class GraphicsInputTests(unittest.TestCase):
    def test_hmp_keyboard_creates_file_through_expected_shortcuts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'monitor.sock'
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(str(path))
            listener.listen(1)
            commands = []
            errors = []

            def serve():
                try:
                    with listener.accept()[0] as client:
                        client.sendall(b'QEMU monitor\r\n(qemu) ')
                        received = b''
                        while True:
                            data = client.recv(1024)
                            if not data:
                                return
                            received += data
                            while b'\n' in received:
                                line, received = received.split(b'\n', 1)
                                commands.append(line.decode('ascii'))
                                client.sendall(b'(qemu) ')
                except Exception as error:  # Propagate failures from the server thread.
                    errors.append(error)

            thread = Thread(target=serve, daemon=True)
            thread.start()
            try:
                boot_test.graphics_key_input(path, time.monotonic() + 5)
                thread.join(timeout=2)
            finally:
                listener.close()
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(commands, [
                'sendkey f', 'sendkey n', 'sendkey t', 'sendkey e',
                'sendkey s', 'sendkey t', 'sendkey dot', 'sendkey t',
                'sendkey x', 'sendkey t', 'sendkey ret',
            ])

    def test_guest_check_requires_file_created_by_gui(self):
        command = boot_test.graphics_guest_command()
        readiness = boot_test.graphics_ready_command()
        self.assertIn(b'NEKO_DESKTOP_INPUT_READY', readiness)
        self.assertIn(b'/run/neko/services/desktop.log', readiness)
        self.assertIn(b'test -f /home/neko/test.txt && ', command)
        self.assertIn(b"'GUI_FILE_' 'CREATED'", command)
        markers = [
            'GRAPHICS_READY', 'NEKO_SESSION_READY',
            'DESKTOP_INPUT_READY',
            'NEKO_DESKTOP_FRAME_READY width=1024 height=768 depth=32',
        ]
        self.assertFalse(boot_test.graphics_markers_present(markers))
        self.assertTrue(boot_test.graphics_markers_present(
            markers + ['GUI_FILE_CREATED']))

    def test_hmp_rejects_command_errors(self):
        client, server = socket.socketpair()
        try:
            server.sendall(b'Error: invalid key\r\n(qemu) ')
            with self.assertRaisesRegex(RuntimeError, 'rejected command'):
                boot_test.hmp_response(client, time.monotonic() + 1)
        finally:
            client.close()
            server.close()


if __name__ == '__main__':
    unittest.main()
