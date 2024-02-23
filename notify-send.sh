#!/bin/sh

# Calls notify-send to send notifications to all local graphical environments.
# This is not easily done from a different user (root), hence this script.

title="wg-monitor"
icon="network-wireless-disconnected"
urgency="normal"

./as-gui-user.sh \
    /usr/bin/notify-send \
    --icon="$icon" \
    --urgency="$urgency" \
    "$title" \
    "$1"
