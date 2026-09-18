#!/bin/bash
set -Eeuo pipefail

# Ensure graphical display is available
export DISPLAY="${DISPLAY:-:0}"

# Ensure secondary partitions (Documentos, Juegos) are mounted
if command -v udisksctl &> /dev/null; then
    udisksctl mount -b /dev/sda1 &> /dev/null || true
    udisksctl mount -b /dev/nvme1n1p3 &> /dev/null || true
fi

# Close all active Conky instances and previous media daemon
pkill -9 -x conky 2>/dev/null || true
pkill -f "playerctl-info.sh --daemon" 2>/dev/null || true
sleep 0.5s

# Initialize cover art cache if missing
if [[ ! -f /tmp/conky_cover.png && -f "$HOME/.config/conky/Mimosa/assets/default_cover.png" ]]; then
    cp "$HOME/.config/conky/Mimosa/assets/default_cover.png" /tmp/conky_cover.png 2>/dev/null || true
fi

# Launch background playerctl sync daemon (decoupled, non-blocking)
if [[ -x "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" ]]; then
    setsid "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" --daemon </dev/null &>/dev/null &
fi

# Launch System Monitor widget (1 Hz refresh rate, stable network meters and graphs)
if [[ -f "$HOME/.config/conky/Mimosa/Mimosa.conf" ]]; then
    setsid conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" </dev/null &>/dev/null &
fi

# Launch Media Player companion widget (20 FPS smooth 33⅓ RPM turntable vinyl & wave bar)
if [[ -f "$HOME/.config/conky/Mimosa/Mimosa-media.conf" ]]; then
    setsid conky -c "$HOME/.config/conky/Mimosa/Mimosa-media.conf" </dev/null &>/dev/null &
fi

disown -a 2>/dev/null || true
exit 0
