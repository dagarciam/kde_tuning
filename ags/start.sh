#!/bin/bash
set -Eeuo pipefail

# Mimosa AGS launcher. Needs a Wayland session (wlr-layer-shell via KWin).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v ags &> /dev/null; then
    echo "mimosa-ags: ags not installed (AUR: aylurs-gtk-shell)" >&2
    exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "mimosa-ags: not running in a Wayland session; skipping." >&2
    exit 0
fi

# Stop a previous instance, then ensure media daemon and default cover exist.
ags quit -i mimosa &> /dev/null || true
pkill -f "ags run $DIR/app.tsx" 2> /dev/null || true
sleep 0.3

if [[ -x "$DIR/scripts/playerctl-info.sh" ]]; then
    pkill -f "playerctl-info.sh --daemon" 2> /dev/null || true
    nohup "$DIR/scripts/playerctl-info.sh" --daemon < /dev/null &> /dev/null &
fi

nohup ags run "$DIR/app.tsx" < /dev/null &> "${XDG_RUNTIME_DIR:-/tmp}/mimosa-ags.log" &
disown -a 2> /dev/null || true
exit 0
