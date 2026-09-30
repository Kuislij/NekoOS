#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxi/build.sh'

x11_name=libxi
x11_upstream=libXi
x11_version=1.8.3
x11_sha256=7ad60056f01af4f786cfe93b3a7707447711626fc8da2637bec71a90409babe5
x11_sha512=5fb8273424467c102d3bab01cb273169038ff6fae739f6873ca357be8890c4fd30ba2952bca2759249458796df53ad130e2c9c3674b385602afd13c718faf79a
x11_soname=libXi.so.6
x11_header=X11/extensions/XInput2.h
x11_pc=xi.pc
x11_prerequisites=(xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxext-1.3.7.nspkg
    libxfixes-6.0.2.nspkg)
x11_runtime_needed=(libX11.so.6 libXext.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'libxext>=1.3.7' 'libxfixes>=6.0.2' 'xorgproto>=2025.1')
build_x11_extension
