#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxcursor/build.sh'

x11_name=libxcursor
x11_upstream=libXcursor
x11_version=1.2.3
x11_sha256=fde9402dd4cfe79da71e2d96bb980afc5e6ff4f8a7d74c159e1966afb2b2c2c0
x11_sha512=069a1eb27a0ee1b29b251bb6c2d0688543a791d6862fad643279e86736e1c12ca6fc02b85b8611c225a9735dc00efab84672d42b547baa97304362f0c5ae0b5a
x11_soname=libXcursor.so.1
x11_header=X11/Xcursor/Xcursor.h
x11_pc=xcursor.pc
x11_prerequisites=(xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxrender-0.9.12.nspkg
    libxfixes-6.0.2.nspkg)
x11_runtime_needed=(libX11.so.6 libXrender.so.1 libXfixes.so.3 libc.so)
x11_depends=('libx11>=1.8.13' 'libxrender>=0.9.12' 'libxfixes>=6.0.2' 'xorgproto>=2025.1')
build_x11_extension
