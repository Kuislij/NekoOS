#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxrandr/build.sh'

x11_name=libxrandr
x11_upstream=libXrandr
x11_version=1.5.5
x11_sha256=72b922c2e765434e9e9f0960148070bd4504b288263e2868a4ccce1b7cf2767a
x11_sha512=3cae1d2eb425dd3d3bd89f514a8e4bd9c696170ab6f3882f6db1936c30674b48277f2e485a8e3e47b3093fb1d9a32d2b054b064bd781db039e833b397aeeda9b
x11_soname=libXrandr.so.2
x11_header=X11/extensions/Xrandr.h
x11_pc=xrandr.pc
x11_prerequisites=(xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg libxext-1.3.7.nspkg libxrender-0.9.12.nspkg)
x11_runtime_needed=(libX11.so.6 libXext.so.6 libXrender.so.1 libc.so)
x11_depends=('libx11>=1.8.13' 'libxext>=1.3.7' 'libxrender>=0.9.12'
    'xorgproto>=2025.1')
build_x11_extension
