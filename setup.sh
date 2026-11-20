#!/bin/bash

# ==============================================================================
# KDE Tuning - Post-installation & Desktop Setup Engine (Modular CLI)
# Author: dagarciam
# Supported: Arch/Manjaro, Fedora, Debian/Ubuntu, openSUSE
#
# Usage:
#   ./setup.sh [OPTIONS]
#
# Options:
#   --steps <list>     Comma-separated steps to run:
#                      deps,wayland,fstab,repos,fonts,grub,ags,conky,zsh,plasma,session
#                      (default runs: deps,wayland,fstab,repos,fonts,grub,ags,zsh,plasma,session)
#   --conky            Use Conky widget instead of Mimosa AGS
#   --dry-run          Simulate actions without modifying the system
#   --no-restart       Skip Plasma Shell restart at the end
#   --rollback [dir]   Rollback KDE config from the latest (or specified) backup
#   -h, --help         Show this help message
# ==============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_DIR="$SCRIPT_DIR"

# Runtime flags (defaults)
DRY_RUN=false
NO_RESTART=false
ROLLBACK_MODE=false
ROLLBACK_DIR=""
USE_CONKY=false
SELECTED_STEPS=()

# All available steps in execution order
ALL_STEPS=(deps wayland fstab repos fonts grub ags conky zsh plasma session)
DEFAULT_STEPS=(deps wayland fstab repos fonts grub ags zsh plasma session)

# Unique log file per run
LOG_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/kde-tuning-${LOG_TIMESTAMP}.log"

# --- Import Core & Modules ---
source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/ini.sh"
source "$SCRIPT_DIR/lib/distro.sh"
source "$SCRIPT_DIR/lib/wayland.sh"
source "$SCRIPT_DIR/lib/fstab.sh"
source "$SCRIPT_DIR/lib/repos_fonts.sh"
source "$SCRIPT_DIR/lib/grub.sh"
source "$SCRIPT_DIR/lib/widgets.sh"
source "$SCRIPT_DIR/lib/zsh.sh"
source "$SCRIPT_DIR/lib/plasma.sh"
source "$SCRIPT_DIR/lib/session.sh"
source "$SCRIPT_DIR/lib/rollback.sh"

# --- Argument Parser ---

show_help() {
    sed -n '3,/^# ===/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --conky|conky)
                USE_CONKY=true
                shift
                ;;
            --steps)
                [[ -z "${2:-}" ]] && error_exit "--steps requires a comma-separated list of steps"
                IFS=',' read -r -a SELECTED_STEPS <<< "$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-restart)
                NO_RESTART=true
                shift
                ;;
            --rollback)
                ROLLBACK_MODE=true
                if [[ -n "${2:-}" && "$2" != --* ]]; then
                    ROLLBACK_DIR="$2"
                    shift
                fi
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                error_exit "Unknown option: $1. Run with --help for usage."
                ;;
        esac
    done

    # Validate --steps values (map deprecated 'x11' -> 'wayland')
    local normalized_steps=()
    for step in "${SELECTED_STEPS[@]}"; do
        if [[ "$step" == "x11" ]]; then
            log_warn "Step 'x11' is deprecated; using 'wayland' instead."
            step="wayland"
        fi
        local valid=false
        for s in "${ALL_STEPS[@]}"; do
            [[ "$step" == "$s" ]] && valid=true && break
        done
        $valid || error_exit "Unknown step: '$step'. Valid steps: ${ALL_STEPS[*]}"
        normalized_steps+=("$step")
    done
    SELECTED_STEPS=("${normalized_steps[@]}")

    # Validate --rollback combinations
    if $ROLLBACK_MODE; then
        for step in "${SELECTED_STEPS[@]}"; do
            [[ "$step" == "plasma" ]] && error_exit "--rollback cannot be combined with --steps containing 'plasma' (conflicting write/restore)."
        done
    fi

    # Default: run DEFAULT_STEPS (ags by default, or conky if --conky was passed)
    if [[ ${#SELECTED_STEPS[@]} -eq 0 ]] && ! $ROLLBACK_MODE; then
        for s in "${DEFAULT_STEPS[@]}"; do
            if $USE_CONKY && [[ "$s" == "ags" ]]; then
                SELECTED_STEPS+=("conky")
            else
                SELECTED_STEPS+=("$s")
            fi
        done
    elif $USE_CONKY; then
        # If --conky was combined with --steps, replace 'ags' with 'conky'
        local updated_steps=()
        for s in "${SELECTED_STEPS[@]}"; do
            if [[ "$s" == "ags" ]]; then
                updated_steps+=("conky")
            else
                updated_steps+=("$s")
            fi
        done
        SELECTED_STEPS=("${updated_steps[@]}")
    fi
}

step_is_selected() {
    local step="$1"
    for s in "${SELECTED_STEPS[@]}"; do
        [[ "$s" == "$step" ]] && return 0
    done
    return 1
}

# --- Execution ---

setup_user_and_home
parse_args "$@"
detect_distro

log_info "Log file: $LOG_FILE"
log_info "Running as user: $REAL_USER (home: $REAL_HOME)"
log_info "Detected distro: $DISTRO_ID (family: $DISTRO_FAMILY, pkg: $PKG_MANAGER)"

if $DRY_RUN; then
    log_warn "DRY-RUN mode: no system changes will be made."
fi

if $ROLLBACK_MODE; then
    do_rollback
    exit 0
fi

preflight_checks

# Only request sudo if a step that needs it is selected
if step_is_selected "deps" || step_is_selected "wayland" || step_is_selected "fstab" || step_is_selected "grub" || step_is_selected "zsh"; then
    if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null && ! $DRY_RUN; then
        if sudo -n true 2>/dev/null; then
            keep_sudo_alive
        else
            log_warn "Some tasks require administrator privileges (sudo)."
            sudo -v || exit 1
            keep_sudo_alive
        fi
    fi
fi

# Calculate total steps to show progress correctly
TOTAL_STEPS=${#SELECTED_STEPS[@]}
CURRENT_STEP=0

for step in "${ALL_STEPS[@]}"; do
    if step_is_selected "$step"; then
        (( CURRENT_STEP++ )) || true
        case "$step" in
            deps)    run_step "Install dependencies"           install_dependencies      "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            wayland) run_step "Configure Wayland session"      configure_wayland_session "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            fstab)   run_step "Configure fstab automounts"     setup_fstab               "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            repos)   run_step "Install external repos"         install_external_repos    "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            fonts)   run_step "Install fonts"                  install_fonts             "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            grub)    run_step "Install GRUB2 theme"            setup_grub_theme          "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            ags)     run_step "Setup AGS widget (Default)"     setup_ags                 "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            conky)   run_step "Setup Conky widget (Optional)"  setup_conky               "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            zsh)     run_step "Setup Zsh"                      setup_zsh                 "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            plasma)  run_step "Restore Plasma config"          restore_plasma_config     "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            session) run_step "Apply session changes"          apply_session_changes     "$CURRENT_STEP" "$TOTAL_STEPS" ;;
        esac
    fi
done

if $DRY_RUN; then
    log_ok "Dry-run complete. No changes were made."
else
    log_ok "Setup finished! Please restart your session if you didn't logout already."
fi
