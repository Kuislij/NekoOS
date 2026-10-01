#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
case "${1:-help}" in
    iso) exec bash "$root/scripts/arch-iso.sh" "${@:2}" ;;
    build) exec bash "$root/scripts/arch-build.sh" "${@:2}" ;;
    run|test) exec python3 "$root/tools/arch_vm.py" "$@" ;;
    help|--help|-h) printf 'NekoOS on Arch\nUsage: bash os arch build\n       bash os arch run [--headless] [--no-build] [--uefi]\n       bash os arch test [--headless] [--no-build] [--uefi] [--timeout SECONDS]\n       bash os arch iso {build|run|test|verify}\n' ;;
    *) printf 'Unknown Arch command: %s\n' "$1" >&2; exit 2 ;;
esac
