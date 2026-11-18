#!/bin/bash
# ==============================================================================
# lib/session.sh - Finalizing desktop session changes
# ==============================================================================

[[ -n "${_LIB_SESSION_LOADED:-}" ]] && return 0
_LIB_SESSION_LOADED=1

apply_session_changes() {
    log_progress "$1" "$2" "Finalizing changes"

    if $NO_RESTART; then
        log_info "Skipping Plasma Shell restart (--no-restart)"
        log_ok "Session changes skipped"
        return 0
    fi

    local current_session="${XDG_SESSION_TYPE:-unknown}"

    if $DRY_RUN; then
        log_dry "Would restart Plasma Shell (session: $current_session)"
        log_ok "Session changes (dry-run)"
        return 0
    fi

    if [ "$current_session" = "wayland" ]; then
        log_info "You are on Wayland: no Plasma Shell restart needed."
        log_info "SDDM is configured to use the Plasma Wayland session."
    else
        log_info "Current session is '$current_session'. Log out and log back in to enter the configured Plasma Wayland session."
    fi

    log_ok "Session finalized"
}
