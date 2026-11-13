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

# Stop a previous instance, then ensure default cover exists for the media card.
ags quit -i mimosa &> /dev/null || true
pkill -f "ags run $DIR/app.tsx" 2> /dev/null || true
sleep 0.3

nohup ags run "$DIR/app.tsx" < /dev/null &> "${XDG_RUNTIME_DIR:-/tmp}/mimosa-ags.log" &
disown -a 2> /dev/null || true
exit 0
