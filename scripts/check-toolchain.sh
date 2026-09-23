#!/usr/bin/env bash
set -euo pipefail
if (( $# )); then
    echo 'Usage: bash scripts/check-toolchain.sh' >&2
    exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash "$root/scripts/bootstrap-dev.sh"
mkdir -p "$root/build/logs" "$root/build/smoke"
exec > >(tee "$root/build/logs/toolchain-check.log") 2>&1
cd "$root/build/smoke"
gcc --version
make --version
ninja --version
printf '#include <stdio.h>\nint main(void) { puts("TOOLCHAIN_READY"); return 0; }\n' > hello.c
printf 'hello-make: hello.c\n\tgcc -Wall -Wextra -Werror hello.c -o hello-make\n' > Makefile
make --always-make
[[ "$(./hello-make)" == TOOLCHAIN_READY ]]
printf 'rule cc\n  command = gcc -Wall -Wextra -Werror $in -o $out\nbuild hello-ninja: cc hello.c\n' > build.ninja
ninja
[[ "$(./hello-ninja)" == TOOLCHAIN_READY ]]
echo 'BUILD_CHECK_PASSED (host toolchain only; no OS image yet)'
