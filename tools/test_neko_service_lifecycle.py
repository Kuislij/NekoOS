"""Isolated host test for foreground neko-service lifecycle actions.

Run on Linux with: python3 tools/test_neko_service_lifecycle.py
"""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "rootfs/usr/bin/neko-service"


class ServiceLifecycleTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="neko-service-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.builtin = self.root / "builtin"
        self.local = self.root / "local"
        self.enabled = self.root / "enabled"
        self.disabled = self.root / "disabled"
        self.runtime = self.root / "run"
        for directory in (self.builtin, self.local, self.enabled,
                          self.disabled, self.runtime):
            directory.mkdir()
        self.manifest = self.root / "boot-services"
        self.manifest.write_text("network\n")
        source = SOURCE.read_text()
        for key, value in {
            "builtin": self.builtin,
            "manifest": self.manifest,
            "local_services": self.local,
            "enabled": self.enabled,
            "disabled": self.disabled,
            "failed": self.runtime,
        }.items():
            source = source.replace(f"{key}=" + {
                "builtin": "/etc/neko/services",
                "manifest": "/etc/neko/boot-services",
                "local_services": "/usr/local/etc/neko/services",
                "enabled": "/var/lib/neko-services/enabled",
                "disabled": "/var/lib/neko-services/disabled",
                "failed": "/run/neko/services",
            }[key], f"{key}={value}", 1)
        self.program = self.root / "neko-service"
        self.program.write_text(source)
        self.write_service(self.local / "ticker", """#!/bin/sh
# neko-service: foreground
case "$1" in
    run) exec sleep 30 ;;
    *) exit 2 ;;
esac
""")
        self.write_service(self.local / "broken", """#!/bin/sh
# neko-service: foreground
case "$1" in run) exit 1 ;; *) exit 2 ;; esac
""")
        self.write_service(self.builtin / "network", """#!/bin/sh
case "$1" in
    start) echo 'NETWORK_READY' ;;
    stop) echo 'network stopped' ;;
    status) echo 'network online' ;;
    *) exit 2 ;;
esac
""")

    def tearDown(self):
        pidfile = self.runtime / "ticker.pid"
        if pidfile.exists():
            self.command("stop", "ticker")

    @staticmethod
    def write_service(path, content):
        path.write_text(content)
        path.chmod(0o755)

    def command(self, *args):
        return subprocess.run(["sh", str(self.program), *args],
                              text=True, capture_output=True, timeout=12)

    def test_foreground_lifecycle_and_legacy_service(self):
        result = self.command("status", "ticker")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("ticker: stopped", result.stdout)

        result = self.command("start", "ticker")
        self.assertEqual(result.returncode, 0, result.stderr)
        first = (self.runtime / "ticker.pid").read_text()
        self.assertIn("ticker: running", self.command("status", "ticker").stdout)
        self.assertEqual(self.command("start", "ticker").returncode, 0)
        self.assertEqual((self.runtime / "ticker.pid").read_text(), first)

        result = self.command("restart", "ticker")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual((self.runtime / "ticker.pid").read_text(), first)
        self.assertEqual(self.command("stop", "ticker").returncode, 0)
        self.assertFalse((self.runtime / "ticker.pid").exists())
        self.assertEqual(self.command("stop", "ticker").returncode, 0)

        # A stale or forged PID record must not signal an unrelated process.
        (self.runtime / "ticker.pid").write_text(f"{os.getpid()} 0\n")
        self.assertEqual(self.command("stop", "ticker").returncode, 0)
        self.assertFalse((self.runtime / "ticker.pid").exists())

        self.assertEqual(self.command("start", "network").stdout.strip(),
                         "NETWORK_READY")
        self.assertIn("network online", self.command("status", "network").stdout)
        self.assertEqual(self.command("restart", "network").returncode, 0)

    def test_boot_autostart_and_failed_run(self):
        (self.enabled / "ticker").touch()
        (self.enabled / "broken").touch()
        result = self.command("boot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NETWORK_READY", result.stdout)
        self.assertIn("Starting service: ticker", result.stdout)
        self.assertIn("SERVICE_FAILED:broken", result.stdout)
        self.assertIn("SYSTEM_READY", result.stdout)
        self.assertTrue((self.runtime / "broken.failed").exists())
        self.assertEqual(self.command("status", "ticker").returncode, 0)


if __name__ == "__main__":
    unittest.main()
