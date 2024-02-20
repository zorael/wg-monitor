#!/bin/sh

# Simple wrapper around notify-send to send notifications to a user's desktop.
# This is not easily done from a different user (root), hence this script.

title="wg-monitor"

#display=":$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##' | head -n 1)"
display=":0"  # change as necessary
user=$(who | grep "($display)" | awk '{ print $1 }' | head -n 1)
uid=$(id -u $user)

/usr/bin/sudo -u $user \
    DISPLAY=$display \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
    /usr/bin/notify-send \
    "$title" "$1"
