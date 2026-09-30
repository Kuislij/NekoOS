#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxdamage/build.sh'

x11_name=libxdamage
x11_upstream=libXdamage
x11_version=1.1.7
x11_sha256=127067f521d3ee467b97bcb145aeba1078e2454d448e8748eb984d5b397bde24
x11_sha512=9406e39cbc426d7fa3c66bf1eec202fdb5af5db99a0ff49c2be995b1ff7326a6c1fb395c46391e1c32f5a6569a5d6e02bdd5b79fc79dd468fc3ebd698496bbc2
x11_soname=libXdamage.so.1
x11_header=X11/extensions/Xdamage.h
x11_pc=xdamage.pc
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
