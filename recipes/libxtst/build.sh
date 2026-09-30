#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxtst/build.sh'

x11_name=libxtst
x11_upstream=libXtst
x11_version=1.2.5
x11_sha256=b50d4c25b97009a744706c1039c598f4d8e64910c9fde381994e1cae235d9242
x11_sha512=848fa580d7abccd48c9ca3440f92e299839ada0912ed60d38d4d4f5bf37431cd02d7059265ab4e524c3e2cb9c368b9b90b863d1ed97d74979ef8811fc5e635a9
x11_soname=libXtst.so.6
x11_header=X11/extensions/XTest.h
x11_pc=xtst.pc
x11_prerequisites=(xorgproto-2025.1.nspkg
    xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg
    libxdmcp-1.1.5.nspkg
    libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg
    libxext-1.3.7.nspkg
    libxfixes-6.0.2.nspkg
    libxi-1.8.3.nspkg)
x11_runtime_needed=(libX11.so.6 libXext.so.6 libXi.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'libxext>=1.3.7' 'libxi>=1.8.3' 'xorgproto>=2025.1')
build_x11_extension
