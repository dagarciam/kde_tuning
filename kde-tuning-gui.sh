#!/bin/bash

# ==============================================================================
# KDE Tuning - Native KDE GUI Launcher (KDialog)
# Author: dagarciam
# Description: KDialog-based front-end for setup.sh.
#              Provides module selection, dry-run/no-restart toggles,
#              live progress display, rollback, and sudo credential handling.
# Requirements: kdialog, bash >= 4.0, setup.sh in the same directory.
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SETUP_SCRIPT="$SCRIPT_DIR/setup.sh"

# --- Sanity checks ---
if ! command -v kdialog &> /dev/null; then
    echo "ERROR: kdialog is not installed. Install it with: sudo pacman -S kdialog" >&2
    exit 1
fi

if [[ ! -x "$SETUP_SCRIPT" ]]; then
    kdialog --error "setup.sh not found or not executable at:\n$SETUP_SCRIPT"
    exit 1
fi

# --- Constants ---
APP_TITLE="KDE Tuning Installer"

declare -A STEP_LABELS=(
    [deps]="System Dependencies (pacman/yay)"
    [x11]="Plasma X11 SDDM Session"
    [repos]="External Themes & Plugins (GitHub)"
    [fonts]="Fonts (Abel, custom TTF)"
    [conky]="Conky Mimosa Widget"
    [zsh]="Zsh & Powerlevel10k Config"
    [plasma]="KDE Plasma Settings & Cursor Theme"
    [session]="Apply Session Changes (Plasma restart)"
)

ALL_STEPS=(deps x11 repos fonts conky zsh plasma session)

# --- Helper: show a checklist dialog and return selected items ---
select_modules() {
    local args=()
    for step in "${ALL_STEPS[@]}"; do
        args+=("$step" "${STEP_LABELS[$step]}" "on")
    done

    kdialog \
        --title "$APP_TITLE" \
        --checklist "Select the installation modules to run:" \
        "${args[@]}" 2>/dev/null
}

# --- Helper: confirm impact before running ---
confirm_run() {
    local selected_steps="$1"
    local dry_run="$2"
    local no_restart="$3"

    local impact_msg=""
    impact_msg+="Modules to run: $(echo "$selected_steps" | tr ' ' ', ')\n\n"
    if [[ "$dry_run" == "true" ]]; then
        impact_msg+="⚠ DRY-RUN: No system changes will be made.\n"
    else
        impact_msg+="⚠ REAL RUN: This will modify your system.\n"
    fi
    [[ "$no_restart" == "true" ]] && impact_msg+="ℹ Plasma Shell restart will be skipped.\n"

    kdialog \
        --title "$APP_TITLE" \
        --warningyesno "$impact_msg\nProceed?" \
        2>/dev/null
}

# --- Helper: ask for sudo password via kdialog ---
request_sudo() {
    local password
    password=$(kdialog \
        --title "$APP_TITLE" \
        --password "Administrator password required for system changes:" \
        2>/dev/null) || return 1

    # Validate the password using a here-string to avoid exposing it in process listings
    if sudo -S true <<< "$password" 2>/dev/null; then
        # Keep sudo alive
        sudo -v 2>/dev/null
        echo "$password"
        return 0
    else
        kdialog --title "$APP_TITLE" --error "Authentication failed. Please check your password."
        return 1
    fi
}

# --- Helper: run setup.sh with a progress dialog ---
run_with_progress() {
    local cmd_args=("$@")
    local log_file
    log_file="$(mktemp /tmp/kde-tuning-gui-XXXXXX.log)"
    local dbus_ref
    local total_steps=0
    local current_step=0

    # Count selected steps from args
    for arg in "${cmd_args[@]}"; do
        if [[ "$arg" == --steps ]]; then
            : # next arg is step list
        fi
    done

    # Create KDialog progress dialog
    dbus_ref=$(kdialog \
        --title "$APP_TITLE" \
        --progressbar "Initializing..." 100 \
        2>/dev/null)

    # Allow user to cancel
    qdbus "$dbus_ref" showCancelButton true 2>/dev/null || true

    # Run setup.sh in background with gui-mode output
    bash "$SETUP_SCRIPT" "${cmd_args[@]}" --gui-mode > "$log_file" 2>&1 &
    local pid=$!

    # Poll output and update progress dialog
    local last_line=""
    while kill -0 "$pid" 2>/dev/null; do
        # Check if user cancelled
        if qdbus "$dbus_ref" wasCancelled 2>/dev/null | grep -q "true"; then
            kill "$pid" 2>/dev/null || true
            qdbus "$dbus_ref" close 2>/dev/null || true
            kdialog --title "$APP_TITLE" --sorry "Installation cancelled by user."
            rm -f "$log_file"
            exit 2
        fi

        # Parse structured output to update progress
        local new_last
        new_last="$(tail -1 "$log_file" 2>/dev/null || true)"
        if [[ "$new_last" != "$last_line" ]]; then
            last_line="$new_last"

            # Parse [PROGRESS:n/total] label
            if [[ "$last_line" =~ ^\[PROGRESS:([0-9]+)/([0-9]+)\]\ (.*) ]]; then
                current_step="${BASH_REMATCH[1]}"
                total_steps="${BASH_REMATCH[2]}"
                local label="${BASH_REMATCH[3]}"
                local pct=$(( (current_step * 100) / total_steps ))
                qdbus "$dbus_ref" Set "" value "$pct" 2>/dev/null || true
                qdbus "$dbus_ref" setLabelText "$label" 2>/dev/null || true

            elif [[ "$last_line" =~ ^\[STEP:ok\]\ (.*) ]]; then
                qdbus "$dbus_ref" setLabelText "✓ ${BASH_REMATCH[1]}" 2>/dev/null || true

            elif [[ "$last_line" =~ ^\[FAIL:(.*)\]\ (.*) ]]; then
                qdbus "$dbus_ref" setLabelText "✗ ${BASH_REMATCH[2]}" 2>/dev/null || true

            elif [[ "$last_line" =~ ^\[DRY-RUN\]\ (.*) ]]; then
                qdbus "$dbus_ref" setLabelText "[DRY-RUN] ${BASH_REMATCH[1]}" 2>/dev/null || true
            fi
        fi

        sleep 0.3
    done

    wait "$pid"
    local exit_code=$?

    qdbus "$dbus_ref" close 2>/dev/null || true

    return "$exit_code"
}

# --- Rollback flow ---
do_rollback_ui() {
    local real_home="${HOME}"
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
        real_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    fi

    # Find available backups
    local backups=()
    while IFS= read -r -d '' dir; do
        backups+=("$dir" "$(basename "$dir")" "off")
    done < <(find "$real_home/.config" -maxdepth 1 -name 'kde_backup_*' -type d -print0 2>/dev/null | sort -z)

    if [[ ${#backups[@]} -eq 0 ]]; then
        kdialog --title "$APP_TITLE" --sorry "No KDE backup directories found in $real_home/.config.\n\nRun the installer first to create a backup."
        return 1
    fi

    local chosen
    chosen=$(kdialog \
        --title "$APP_TITLE" \
        --radiolist "Select the backup to restore from:" \
        "${backups[@]}" \
        2>/dev/null) || return 1

    [[ -z "$chosen" ]] && return 1

    local dry_run_flag=""
    if kdialog --title "$APP_TITLE" --yesno "Run rollback in DRY-RUN mode first? (No changes will be made)" 2>/dev/null; then
        dry_run_flag="--dry-run"
    fi

    kdialog --title "$APP_TITLE" \
        --warningyesno "⚠ Rollback Scope & Limits:\n\n• Only KDE Plasma config files (from the selected backup) will be restored.\n• Package installs, Zsh config, fonts, and external repos are NOT reversed.\n• You will need to restart your session after rollback.\n\nBackup: $(basename "$chosen")\n\nProceed with rollback?" \
        2>/dev/null || return 1

    local log_file
    log_file="$(mktemp /tmp/kde-tuning-rollback-XXXXXX.log)"

    bash "$SETUP_SCRIPT" --rollback "$chosen" ${dry_run_flag:+"$dry_run_flag"} --gui-mode > "$log_file" 2>&1
    local exit_code=$?

    local log_content
    log_content="$(cat "$log_file")"
    rm -f "$log_file"

    if [[ "$exit_code" -eq 0 ]]; then
        kdialog --title "$APP_TITLE" \
            --textbox <(echo "$log_content") \
            600 400 \
            2>/dev/null || true
        kdialog --title "$APP_TITLE" --msgbox "✓ Rollback complete.\n\nRestart your session for all changes to take effect." 2>/dev/null
    else
        kdialog --title "$APP_TITLE" \
            --detailedsorry "Rollback encountered errors." \
            "$log_content" \
            2>/dev/null || kdialog --title "$APP_TITLE" --error "Rollback failed:\n$log_content"
    fi
}

# --- Main GUI flow ---
main() {
    # Main menu
    local action
    action=$(kdialog \
        --title "$APP_TITLE" \
        --menu "KDE Tuning — What would you like to do?" \
        "install" "Install / Apply Configuration" \
        "rollback" "Rollback KDE Config to Previous Backup" \
        2>/dev/null) || exit 2

    if [[ "$action" == "rollback" ]]; then
        do_rollback_ui
        exit $?
    fi

    # --- Module selection ---
    local raw_selection
    raw_selection=$(select_modules) || exit 2
    if [[ -z "$raw_selection" ]]; then
        kdialog --title "$APP_TITLE" --sorry "No modules selected. Nothing to do."
        exit 0
    fi

    # KDialog returns space-separated quoted values; split safely without eval
    local selected_steps=()
    read -r -a selected_steps <<< "$raw_selection"

    # --- Options toggles ---
    local options
    options=$(kdialog \
        --title "$APP_TITLE" \
        --checklist "Installation options:" \
        "dry_run"    "Dry-Run (simulate, no changes)"       "off" \
        "no_restart" "Skip Plasma Shell restart at the end" "off" \
        2>/dev/null) || exit 2

    local dry_run=false
    local no_restart=false
    [[ "$options" == *"dry_run"* ]]    && dry_run=true
    [[ "$options" == *"no_restart"* ]] && no_restart=true

    # --- Build CLI argument list ---
    local cmd_args=()
    cmd_args+=(--steps "$(IFS=','; echo "${selected_steps[*]}")")
    $dry_run    && cmd_args+=(--dry-run)
    $no_restart && cmd_args+=(--no-restart)

    # --- Confirm impact ---
    confirm_run "${selected_steps[*]}" "$dry_run" "$no_restart" || exit 2

    # --- Sudo handling ---
    local needs_root=false
    for step in "${selected_steps[@]}"; do
        [[ "$step" == "deps" || "$step" == "x11" ]] && needs_root=true && break
    done

    if $needs_root && ! $dry_run; then
        if ! sudo -n true 2>/dev/null; then
            request_sudo || exit 1
        fi
    fi

    # --- Execute with progress ---
    local log_file
    log_file="$(mktemp /tmp/kde-tuning-install-XXXXXX.log)"

    # Write output to temp log and also capture
    run_with_progress "${cmd_args[@]}"
    local exit_code=$?

    # Find the actual log written by setup.sh (latest in /tmp)
    local setup_log
    setup_log="$(find /tmp -maxdepth 1 -name 'kde-tuning-*.log' -newer "$SETUP_SCRIPT" 2>/dev/null | sort | tail -1)"

    rm -f "$log_file"

    # --- Result dialog ---
    if [[ "$exit_code" -eq 0 ]]; then
        local msg="✓ Installation complete!"
        $dry_run && msg="✓ Dry-run complete. No changes were made."
        if [[ -n "$setup_log" ]]; then
            kdialog --title "$APP_TITLE" \
                --textbox "$setup_log" \
                700 450 \
                2>/dev/null || true
        fi
        kdialog --title "$APP_TITLE" --msgbox "$msg\n\nLog: ${setup_log:-n/a}" 2>/dev/null
    elif [[ "$exit_code" -eq 2 ]]; then
        kdialog --title "$APP_TITLE" --sorry "Installation was cancelled."
    else
        local error_detail=""
        [[ -n "$setup_log" ]] && error_detail="$(grep '\[FAIL\|ERROR' "$setup_log" 2>/dev/null | head -20 || true)"
        kdialog --title "$APP_TITLE" \
            --detailedsorry "Installation failed (exit code: $exit_code).\n\nSee the log for details:\n${setup_log:-n/a}" \
            "$error_detail" \
            2>/dev/null || kdialog --title "$APP_TITLE" --error "Installation failed (exit code: $exit_code).\n\nLog: ${setup_log:-n/a}"
        exit 1
    fi
}

main "$@"
