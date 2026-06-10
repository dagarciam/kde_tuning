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

# Close all active Conky instances
killall conky 2>/dev/null
sleep 2s

# Launch specific Conky config
conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" &> /dev/null &

exit 0
