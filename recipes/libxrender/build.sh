#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../x11-extension-common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/libxrender/build.sh'

x11_name=libxrender
x11_upstream=libXrender
x11_version=0.9.12
x11_sha256=b832128da48b39c8d608224481743403ad1691bf4e554e4be9c174df171d1b97
x11_sha512=3d24a6877b500608e3e2a393532a99d4fd54fc343375d8fb51dfbb1b50cedf002c7722f771cf7776f93cb6e0421ca5966ce45435cb402d5f12a398f9ea743474
x11_soname=libXrender.so.1
x11_header=X11/extensions/Xrender.h
x11_pc=xrender.pc
x11_prerequisites=(xorgproto-2025.1.nspkg xtrans-1.6.0.nspkg
    libxau-1.0.12.nspkg libxdmcp-1.1.5.nspkg libxcb-1.17.0.nspkg
    libx11-1.8.13.nspkg)
x11_runtime_needed=(libX11.so.6 libc.so)
x11_depends=('libx11>=1.8.13' 'xorgproto>=2025.1')
build_x11_extension
