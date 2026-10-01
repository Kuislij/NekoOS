#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ $# == 0 ]] || { echo 'Usage: bash os arch iso build' >&2; exit 2; }
bash "$root/scripts/arch-build.sh" --bootstrap-only
echo 'Собираю NekoOS Live ISO; подробности: build/logs/arch-iso-build.log'
python3 - "$root" "$(id -u)" "$(id -g)" "${WSL_DISTRO_NAME:-}" <<'PY'
from pathlib import Path
import shutil, subprocess, sys
root = Path(sys.argv[1])
sys.path.insert(0, str(root / 'tools'))
from arch_vm import open_guarded_log
helper = ['bash', str(root / 'scripts/arch-iso-build-root.sh'), str(root), sys.argv[2], sys.argv[3]]
command = (['wsl.exe', '-d', sys.argv[4], '-u', 'root', '--'] + helper
           if sys.argv[4] and shutil.which('wsl.exe') else ['sudo', '--'] + helper)
with open_guarded_log(root / 'build/logs/arch-iso-build.log') as output:
    subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True)
PY
python3 "$root/tools/arch_iso.py" verify
echo 'NEKO_LIVE_ISO_BUILT: out/arch/iso/nekoos-live-x86_64.iso'
