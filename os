#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
    doctor) exec bash "$root/scripts/bootstrap-dev.sh" "${@:2}" ;;
    check) exec bash "$root/scripts/check-dev.sh" "${@:2}" ;;
    image) exec bash "$root/scripts/create-disk.sh" "${@:2}" ;;
    system-image) exec bash "$root/scripts/create-system-disk.sh" "${@:2}" ;;
    system-update) exec python3 "$root/tools/system_update.py" apply "${@:2}" ;;
    system-rollback) exec python3 "$root/tools/system_update.py" rollback "${@:2}" ;;
    build|run) exec bash "$root/scripts/$1.sh" "${@:2}" ;;
    iso) exec bash "$root/scripts/create-iso.sh" "${@:2}" ;;
    test) exec python3 "$root/tools/boot_test.py" "${@:2}" ;;
    help|--help|-h) printf 'NekoOS\nUsage: bash os {doctor|check|build|image|system-image|system-update|system-rollback|iso|run|test|help}\n' ;;
    *) printf 'Unknown command: %s\n' "$1" >&2; exit 2 ;;
esac
