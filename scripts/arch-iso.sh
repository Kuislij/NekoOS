#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
case "${1:-help}" in
  build) exec bash "$root/scripts/arch-iso-build.sh" "${@:2}" ;;
  run|test|verify) exec python3 "$root/tools/arch_iso.py" "$@" ;;
  help|--help|-h) printf 'NekoOS Live ISO\nUsage: bash os arch iso build\n       bash os arch iso run [--no-build] [--headless] [--uefi] [--usb]\n       bash os arch iso test [--no-build] [--headless] [--timeout SECONDS]\n' ;;
  *) echo "Unknown ISO action: $1" >&2; exit 2 ;;
esac
