#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxcomposite/build.sh'

x11_name=libxcomposite
x11_upstream=libXcomposite
x11_version=0.4.7
x11_sha256=8bdf310967f484503fa51714cf97bff0723d9b673e0eecbf92b3f97c060c8ccb
x11_sha512=24a03e3242f22b113aa6a3f9341858c072730f0f0073a1a7b9d36b982cd5b77223151aad32b61d1a38bbcb9f8ffedaf67b882dcb95f197d80ece9dbc99332c36
x11_soname=libXcomposite.so.1
x11_header=X11/extensions/Xcomposite.h
x11_pc=xcomposite.pc
x11_prerequisites=(xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxfixes-6.0.2.nspkg)
x11_runtime_needed=(libX11.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'libxfixes>=6.0.2' 'xorgproto>=2025.1')
build_x11_extension
