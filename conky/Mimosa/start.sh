#!/bin/bash

# Check if we are in an X11 session
# Mimosa Conky uses Xlib bindings which are not compatible with Wayland
if [ "$XDG_SESSION_TYPE" != "x11" ]; then
    echo "Mimosa Conky requires an X11 session. Current session: $XDG_SESSION_TYPE"
    # Optional: notify the user via desktop notification
    if command -v notify-send &> /dev/null; then
        notify-send "Conky Error" "Mimosa theme requires an X11 session to display Lua rings correctly."
    fi
    exit 1
fi

# Ensure secondary partitions (Documentos, Juegos) are mounted
if command -v udisksctl &> /dev/null; then
    udisksctl mount -b /dev/sda1 &> /dev/null || true
    udisksctl mount -b /dev/nvme1n1p3 &> /dev/null || true
fi

# Close all active Conky instances
killall conky 2>/dev/null
sleep 2s

# Initialize cover art cache if missing
if [ ! -f /tmp/conky_cover.png ] && [ -f "$HOME/.config/conky/Mimosa/assets/default_cover.png" ]; then
    cp "$HOME/.config/conky/Mimosa/assets/default_cover.png" /tmp/conky_cover.png 2>/dev/null || true
fi

# Launch specific Conky config
conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" &> /dev/null &

exit 0
