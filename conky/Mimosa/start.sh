#!/bin/bash
set -Eeuo pipefail

# Ensure graphical display is available
export DISPLAY="${DISPLAY:-:0}"

# Ensure secondary named partitions (Documentos, Juegos, Personal) are mounted if present
if command -v udisksctl &> /dev/null; then
    for vol_label in Documentos Juegos Personal; do
        if [[ -e "/dev/disk/by-label/$vol_label" ]] && ! findmnt -rn -S "LABEL=$vol_label" &>/dev/null; then
            udisksctl mount -b "/dev/disk/by-label/$vol_label" &> /dev/null || true
        fi
    done
fi

# Close all active Conky instances and previous media daemon
pkill -9 -x conky 2>/dev/null || true
pkill -f "playerctl-info.sh --daemon" 2>/dev/null || true
sleep 0.5s

# Run hardware auto-detection (updates lib/hw_config.lua and active network interface)
if [[ -x "$HOME/.config/conky/Mimosa/scripts/hw-detect.sh" ]]; then
    "$HOME/.config/conky/Mimosa/scripts/hw-detect.sh" >/dev/null 2>&1 || true
fi

# Initialize cover art cache if missing
if [[ ! -f /tmp/conky_cover.png && -f "$HOME/.config/conky/Mimosa/assets/default_cover.png" ]]; then
    cp "$HOME/.config/conky/Mimosa/assets/default_cover.png" /tmp/conky_cover.png 2>/dev/null || true
fi

# Pre-populate media state and vinyl cover synchronously (3ms) so Conky finds them immediately
if [[ -x "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" ]]; then
    "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" -s >/dev/null 2>&1 || true
fi

# Launch background playerctl sync daemon (decoupled, non-blocking)
if [[ -x "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" ]]; then
    nohup "$HOME/.config/conky/Mimosa/scripts/playerctl-info.sh" --daemon </dev/null &>/dev/null &
fi

# Launch System Monitor widget (1 Hz refresh rate, stable network meters and graphs)
if [[ -f "$HOME/.config/conky/Mimosa/Mimosa.conf" ]]; then
    nohup conky -c "$HOME/.config/conky/Mimosa/Mimosa.conf" </dev/null &>/dev/null &
fi

# Launch Media Player companion widget (20 FPS smooth 33⅓ RPM turntable vinyl & wave bar)
if [[ -f "$HOME/.config/conky/Mimosa/Mimosa-media.conf" ]]; then
    nohup conky -c "$HOME/.config/conky/Mimosa/Mimosa-media.conf" </dev/null &>/dev/null &
fi

disown -a 2>/dev/null || true
exit 0
