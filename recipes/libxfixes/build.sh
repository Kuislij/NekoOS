#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxfixes/build.sh'

x11_name=libxfixes
x11_upstream=libXfixes
x11_version=6.0.2
x11_sha256=39f115d72d9c5f8111e4684164d3d68cc1fd21f9b27ff2401b08fddfc0f409ba
x11_sha512=87542927ba9839fdd83282b0fba1bd2afae853ffe4e0f5f548915de22432bbc34a064578ba8527ba6041a993ee27390ba6ee2f1a957cb961717d45026e40ec75
x11_soname=libXfixes.so.3
x11_header=X11/extensions/Xfixes.h
x11_pc=xfixes.pc
x11_prerequisites=(xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg)
x11_runtime_needed=(libX11.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'xorgproto>=2025.1')
build_x11_extension
