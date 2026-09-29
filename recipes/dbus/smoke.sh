#!/usr/bin/env bash
# Exercise the staged musl daemon and session runner with a temporary bus.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/../../scripts/common.sh"
(( $# == 0 )) || die 'Usage: bash recipes/dbus/smoke.sh'
work="$root/build/system-package-build/dbus-1.16.2"
stage="$work/stage"
sysroot="$work/sysroot"
loader="$root/build/toolchain-root/usr/lib/libc.so"
library_path="$stage/usr/lib:$sysroot/usr/lib"
[[ -x "$loader" && -x "$stage/usr/bin/dbus-run-session" &&
   -x "$stage/usr/bin/dbus-daemon" &&
   -f "$stage/usr/share/dbus-1/session.conf" ]] ||
    die 'Build the D-Bus package before running its session-bus smoke test.'

# Once GLib has been built, exercise its packaged musl gdbus client as well as
# the packaged musl bus and session runner. The host client remains useful when
# checking this D-Bus recipe before the later GLib build has completed.
glib_work="$root/build/system-package-build/glib-2.84.4"
if [[ -x "$glib_work/stage/usr/bin/gdbus" ]]; then
    library_path="$glib_work/stage/usr/lib:$glib_work/sysroot/usr/lib:$library_path"
    gdbus_command=("$loader" --library-path "$library_path"
        "$glib_work/stage/usr/bin/gdbus")
    client=musl-gdbus
else
    command -v gdbus >/dev/null || die 'gdbus is required on the Linux test host.'
    gdbus_command=(gdbus)
    client=host-gdbus
fi

wrapper="$work/test-dbus-daemon.sh"
cat > "$wrapper" <<EOF
#!/bin/sh
exec "$loader" --library-path "$library_path" "$stage/usr/bin/dbus-daemon" "\$@"
EOF
chmod 755 "$wrapper"

result="$("$loader" --library-path "$library_path" \
    "$stage/usr/bin/dbus-run-session" \
    --dbus-daemon="$wrapper" \
    --config-file="$stage/usr/share/dbus-1/session.conf" -- \
    "${gdbus_command[@]}" call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.ListNames)"
[[ "$result" == *org.freedesktop.DBus* ]] ||
    die "D-Bus session did not return its well-known name: $result"
printf 'DBUS_SESSION_READY (%s): %s\n' "$client" "$result"
