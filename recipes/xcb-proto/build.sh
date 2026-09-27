#!/usr/bin/env bash
# Stage the XCB protocol descriptions and Python generator for the build host.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/xcb-proto/build.sh'

xcb_proto_version=1.17.0
xcb_proto_url=https://xorg.freedesktop.org/archive/individual/xcb/xcb-proto-1.17.0.tar.xz
xcb_proto_sha256=2c1bacd2110f4799f74de6ebb714b94cf6f80fb112316b1219480fd22562148c

for tool in curl sha256sum tar make python3; do
    command -v "$tool" >/dev/null || die "$tool is required on the Linux build host."
done

archive="$root/cache/sources/xcb-proto-$xcb_proto_version.tar.xz"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-all-errors --retry-delay 2 --connect-timeout 30 \
        -o "$archive.part" "$xcb_proto_url"
    printf '%s  %s\n' "$xcb_proto_sha256" "$archive.part" | sha256sum -c -
    mv -- "$archive.part" "$archive"
fi
printf '%s  %s\n' "$xcb_proto_sha256" "$archive" | sha256sum -c -

host_tools="$root/build/host-tools"
work="$host_tools/xcb-proto-$xcb_proto_version"
[[ ! -L "$host_tools" && ! -L "$work" ]] ||
    die 'Host tool directories must not be symlinks.'
mkdir -p "$host_tools"
rm -rf -- "$work"
mkdir -p "$work/sources" "$work/build" "$work/stage"
tar --no-same-owner -xf "$archive" -C "$work/sources"
source_dir="$work/sources/xcb-proto-$xcb_proto_version"
build_dir="$work/build"
stage="$work/stage"
python_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
python_path="$stage/usr/lib/python$python_version/site-packages"

# This is a host-side code generator and protocol data, not a guest package.
# Embedding the absolute staging prefix in xcb-proto.pc gives libxcb's host
# configure step a usable xcbincludedir and pythondir without DESTDIR hacks.
(
    cd "$build_dir"
    PYTHON=python3 am_cv_python_pythondir="$python_path" \
        am_cv_python_pyexecdir="$python_path" \
        "$source_dir/configure" --prefix="$stage/usr"
)
make -C "$build_dir" -j "${JOBS:-4}"
make -C "$build_dir" install

pc_dir="$stage/usr/share/pkgconfig"
xml_dir="$stage/usr/share/xcb"
[[ -f "$pc_dir/xcb-proto.pc" && -f "$xml_dir/xproto.xml" &&
   -f "$xml_dir/xcb.xsd" ]] || die 'xcb-proto metadata or XML files are missing.'
[[ -f "$python_path/xcbgen/__init__.py" ]] || die 'xcbgen Python package was not staged.'
PYTHONPATH="$python_path" python3 -c 'import xcbgen; import xcbgen.error'

# libxcb can source this file; paths are also printed for recipe integration.
{
    printf 'XCBPROTO_PKG_CONFIG_PATH=%q\n' "$pc_dir"
    printf 'XCBPROTO_PYTHONPATH=%q\n' "$python_path"
    printf 'XCBPROTO_XCBINCLUDEDIR=%q\n' "$xml_dir"
    cat <<'EOF'
export XCBPROTO_PKG_CONFIG_PATH XCBPROTO_PYTHONPATH XCBPROTO_XCBINCLUDEDIR
export PKG_CONFIG_PATH="$XCBPROTO_PKG_CONFIG_PATH${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export PYTHONPATH="$XCBPROTO_PYTHONPATH${PYTHONPATH:+:$PYTHONPATH}"
export XCBPROTO_XCBINCLUDEDIR
EOF
} > "$work/env.sh"

printf 'XCB_PROTO_HOST_READY: %s\n' "$work"
printf 'PKG_CONFIG_PATH=%s\nPYTHONPATH=%s\nXCBPROTO_XCBINCLUDEDIR=%s\n' \
    "$pc_dir" "$python_path" "$xml_dir"
