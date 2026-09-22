#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-help}" in
    doctor) exec bash "$root/scripts/bootstrap-dev.sh" "${@:2}" ;;
    build|run) exec bash "$root/scripts/$1.sh" "${@:2}" ;;
    help|--help|-h) printf 'NekoOS stage 1\nUsage: bash os {doctor|build|run|help}\n' ;;
    *) printf 'Unknown command: %s\n' "$1" >&2; exit 2 ;;
esac
