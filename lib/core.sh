#!/bin/bash
# ==============================================================================
# lib/core.sh - Logging, environment setup, and system helper functions
# ==============================================================================

[[ -n "${_LIB_CORE_LOADED:-}" ]] && return 0
_LIB_CORE_LOADED=1

# ANSI Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

_log_raw() {
    echo -e "$*" | tee -a "$LOG_FILE"
}

error_exit() {
    echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2
    exit 1
}

log_warn() {
    echo -e "${YELLOW}Warning: $*${NC}" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}==> $*${NC}" | tee -a "$LOG_FILE"
}

log_ok() {
    echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}$*${NC}" | tee -a "$LOG_FILE"
}

log_progress() {
    local current="$1"
    local total="$2"
    local label="$3"
    echo -e "${YELLOW}[${current}/${total}] ${label}${NC}" | tee -a "$LOG_FILE"
}

log_dry() {
    echo -e "${YELLOW}[DRY-RUN] $*${NC}" | tee -a "$LOG_FILE"
}

setup_user_and_home() {
    # Capture the real user and home directory BEFORE any sudo interactions
    if [ "$EUID" -eq 0 ]; then
        if [ -z "${SUDO_USER:-}" ]; then
            error_exit "Do not run this script as root directly. Run it as your desktop user (with sudo privileges)."
        fi
        REAL_USER="${SUDO_USER:-root}"
        REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
    else
        REAL_USER="$USER"
        REAL_HOME="$HOME"
    fi
}

keep_sudo_alive() {
    while true; do
        if ! sudo -n true 2>/dev/null; then
            break
        fi
        sleep 50
        kill -0 "$$" || exit
    done &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

run_as_root() {
    if $DRY_RUN; then
        log_dry "Would run as root: $*"
        return 0
    fi
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo &> /dev/null; then
        if ! sudo -n "$@"; then
            echo -e "${RED}ERROR: sudo command failed: $*${NC}" >&2
            return 1
        fi
    else
        echo -e "${RED}ERROR: Not running as root and sudo unavailable.${NC}" >&2
        return 1
    fi
}

ensure_cmd() {
    local cmd="$1"
    command -v "$cmd" &> /dev/null || error_exit "Required command not found: $cmd"
}

ensure_file() {
    local file_path="$1"
    [ -f "$file_path" ] || error_exit "Required file not found: $file_path"
}

ensure_dir() {
    local dir_path="$1"
    [ -d "$dir_path" ] || error_exit "Required directory not found: $dir_path"
}

dry_cp() {
    if $DRY_RUN; then
        log_dry "cp $*"
    else
        cp "$@"
    fi
}

dry_mkdir() {
    if $DRY_RUN; then
        log_dry "mkdir -p $*"
    else
        mkdir -p "$@"
    fi
}

dry_chmod() {
    if $DRY_RUN; then
        log_dry "chmod $*"
    else
        chmod "$@"
    fi
}

dry_cat_write() {
    local dest="$1"
    shift
    if $DRY_RUN; then
        log_dry "write file: $dest"
    else
        cat > "$dest"
    fi
}

run_step() {
    local name="$1"
    shift
    "$@" || error_exit "Step failed: $name"
}

preflight_checks() {
    log_step "Running preflight checks"

    ensure_cmd getent
    ensure_cmd cp
    ensure_cmd sed

    [ -n "$REAL_USER" ] || error_exit "REAL_USER is empty"
    [ -n "$REAL_HOME" ] || error_exit "REAL_HOME is empty"
    [ -d "$REAL_HOME" ] || error_exit "Home directory does not exist: $REAL_HOME"

    if step_is_selected "wayland"; then
        ensure_dir "$REPO_DIR/sddm"
        ensure_file "$REPO_DIR/sddm/kde_settings.conf"
    fi
    if step_is_selected "conky"; then
        ensure_dir "$REPO_DIR/conky/Mimosa"
        ensure_file "$REPO_DIR/conky/conky-mimosa.desktop"
    fi
    if step_is_selected "ags"; then
        ensure_dir "$REPO_DIR/ags"
        ensure_file "$REPO_DIR/ags/mimosa-ags.desktop"
    fi
    if step_is_selected "fonts"; then
        ensure_file "$REPO_DIR/ags/fonts/Abel-Regular.ttf"
    fi
    if step_is_selected "zsh"; then
        ensure_dir "$REPO_DIR/zsh"
        ensure_file "$REPO_DIR/zsh/.zshrc"
        ensure_file "$REPO_DIR/zsh/.p10k.zsh"
    fi
    if step_is_selected "plasma"; then
        ensure_dir "$REPO_DIR/plasma"
    fi
}
