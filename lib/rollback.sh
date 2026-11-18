#!/bin/bash
# ==============================================================================
# lib/rollback.sh - KDE Plasma backup restoration and rollback engine
# ==============================================================================

[[ -n "${_LIB_ROLLBACK_LOADED:-}" ]] && return 0
_LIB_ROLLBACK_LOADED=1

do_rollback() {
    local target_backup="$ROLLBACK_DIR"

    if [[ -z "$target_backup" ]]; then
        # Find the most recent backup
        if [[ -f "$REAL_HOME/.config/.kde_last_backup" ]]; then
            target_backup="$(cat "$REAL_HOME/.config/.kde_last_backup")"
        else
            # Scan for the newest kde_backup_* dir
            target_backup="$(find "$REAL_HOME/.config" -maxdepth 1 -name 'kde_backup_*' -type d 2>/dev/null | sort | tail -1)"
        fi
    fi

    if [[ -z "$target_backup" || ! -d "$target_backup" ]]; then
        error_exit "No valid backup directory found for rollback. Specify one with --rollback <dir>."
    fi

    log_info "Rolling back KDE config from: $target_backup"
    log_warn "Scope: only KDE Plasma config files backed up during a previous run of this script."
    log_warn "Package installs, fonts, Zsh config, and external repos are NOT reversed."

    local plasma_files=(
        "plasma-org.kde.plasma.desktop-appletsrc" "plasmashellrc"
        "kglobalshortcutsrc" "kwinrc" "kdeglobals" "kactivitymanagerdrc"
    )

    local restored=0
    local skipped=0

    for file in "${plasma_files[@]}"; do
        if [[ -f "$target_backup/$file" ]]; then
            if $DRY_RUN; then
                log_dry "Would restore: $REAL_HOME/.config/$file from $target_backup/$file"
            else
                cp "$target_backup/$file" "$REAL_HOME/.config/$file"
                log_ok "Restored: $file"
            fi
            (( restored++ )) || true
        else
            log_warn "Not in backup, skipping: $file"
            (( skipped++ )) || true
        fi
    done

    if $DRY_RUN; then
        log_ok "Rollback dry-run complete ($restored files would be restored, $skipped skipped)"
    else
        log_ok "Rollback complete ($restored files restored, $skipped skipped)"
        log_info "Backup source: $target_backup"
        log_warn "Restart your session for changes to take full effect."
    fi
}
