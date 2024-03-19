#!/bin/bash

# Simple helper to run a command as all users that are currently running a
# graphical environment, with proper DBUS session environment variables set.
# This is useful for sending desktop notifications and works with notify-send.

IFS=
displays=()

resolve_displays() {
    local display

    while read display; do
        [[ "${display:0:2}" = "(:" ]] || continue
        displays+=( $display )
    done < <(who | awk '{ print $5 }' | sort -u)
}

call_as_user() {
    local user="$1"
    local display="${2:1:-1}"  # slice away the parentheses
    local uid=$(id -u $user)
    shift 2

    /usr/bin/sudo \
        --user=$user \
        DISPLAY=$display \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
        "$@"
}

call_as_all_users() {
    local user
    local display

    for display in ${displays[@]}; do
        user=$(who | grep -G "$display" | awk '{ print $1 }' | head -n1)
        [[ "$user" ]] || continue  # should always hold
        call_as_user $user $display "$@"
    done
}

if [[ $# = 0 ]]; then
    echo "usage: ${0##*/} [command] [args...]"
    exit 0
fi

resolve_displays

if [[ ${#displays[@]} = 0 ]]; then
    echo "No graphical environments found."
    exit 1
fi

call_as_all_users "$@"
