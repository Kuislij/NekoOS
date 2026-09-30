#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxinerama/build.sh'

x11_name=libxinerama
x11_upstream=libXinerama
x11_version=1.1.6
x11_sha256=d00fc1599c303dc5cbc122b8068bdc7405d6fcb19060f4597fc51bd3a8be51d7
x11_sha512=64bff837941625120da43b8876db4204bc5740bcf3147997fc4df1475f90d6d9e3f9caa8748c7ebbf69d681be8e5ab4bc40f82c56c367dddcec3ab27d1c71573
x11_soname=libXinerama.so.1
x11_header=X11/extensions/Xinerama.h
x11_pc=xinerama.pc
x11_prerequisites=(xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxext-1.3.7.nspkg)
x11_runtime_needed=(libX11.so.6 libXext.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'libxext>=1.3.7' 'xorgproto>=2025.1')
build_x11_extension
