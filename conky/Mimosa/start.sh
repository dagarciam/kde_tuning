#!/bin/bash

# Ensure graphical display is available
export DISPLAY="${DISPLAY:-:0}"

# Ensure secondary partitions (Documentos, Juegos) are mounted
if command -v udisksctl &> /dev/null; then
    udisksctl mount -b /dev/sda1 &> /dev/null || true
    udisksctl mount -b /dev/nvme1n1p3 &> /dev/null || true
fi

# Close all active Conky instances
pkill -9 -x conky 2>/dev/null || true
sleep 1s

# Initialize cover art cache if missing
if [ ! -f /tmp/conky_cover.png ] && [ -f "$HOME/.config/conky/Mimosa/assets/default_cover.png" ]; then
    cp "$HOME/.config/conky/Mimosa/assets/default_cover.png" /tmp/conky_cover.png 2>/dev/null || true
fi

# Launch specific Conky config detached from terminal
setsid nohup conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" </dev/null &>/dev/null &

exit 0
