#!/bin/bash

# Simple helper to run a command as all users that are currently running a
# graphical environment, with proper DBUS session environment variables set.
# This is useful for sending desktop notifications and works with notify-send.

call_as_user() {
    local user="$1"
    local display="$2"
    local uid=$(id -u $user)
    shift 2

    /usr/bin/sudo \
        --user=$user \
        DISPLAY=$display \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
        "$@"
}

if [[ $# -eq 0 ]]; then
    echo "usage: ${0##*/} [command] [args...]"
    exit 0
fi

all_displays=( $(ls /tmp/.X11-unix/* 2>/dev/null | sed 's#/tmp/.X11-unix/X##') )

if [[ ${#all_displays[@]} -eq 0 ]]; then
    echo "No graphical environments found."
    exit 1
fi

for display_num in ${all_displays[@]}; do
    display=":$display_num"
    user=$(who | grep "($display)" | awk '{ print $1 }' | head -n 1)
    [[ "$user" ]] || continue
    call_as_user $user $display "$@"
done
