#!/bin/bash

# Calls notify-send to send notifications to all local graphical environments.
# This is not easily done from a different user (root), hence this script.

# Skip the initial notification on startup (main loop iteration 0).
[[ "$2" = "0" ]] && exit 0

title="wg-monitor"
icon="network-wireless-disconnected"
urgency="critical"

./as-gui-user.sh \
    /usr/bin/notify-send \
    --icon="$icon" \
    --urgency="$urgency" \
    "$title" \
    "$1"
