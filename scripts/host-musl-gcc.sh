#!/bin/sh
# Use the pinned, locally staged musl to build host-runnable guest tools.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P) || exit 1
exec gcc -specs "$root/build/host-musl-gcc.specs" "$@"
