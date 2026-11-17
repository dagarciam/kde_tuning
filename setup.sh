#!/bin/bash

set -Eeuo pipefail

# ==============================================================================
# KDE Tuning - Master Setup Script
# Author: dagarciam
# Description: Automates the deployment of the AGS desktop widget (or Conky with --conky), Zsh, and KDE Wayland configurations.
# Usage:
#   ./setup.sh [OPTIONS]
#
# Options:
#   --conky            Install and configure Conky instead of the default AGS widget.
#   --steps <list>     Comma-separated list of steps to run.
#                      Steps: deps,wayland,fstab,repos,fonts,ags,conky,zsh,plasma,session
#                      (default runs: deps,wayland,fstab,repos,fonts,ags,zsh,plasma,session)
#   --dry-run          Simulate all changes without modifying files or system.
#   --no-restart       Skip Plasma Shell restart at the end.
#   --gui-mode         Emit structured log prefixes for GUI consumption.
#   --rollback [dir]   Restore KDE config from a kde_backup directory.
#                      Uses the most recent backup if no directory is given.
#   -h, --help         Show this help message.
#
# Exit codes:
#   0  Success
#   1  Error (with message to stderr)
#   2  Cancelled by user
# ==============================================================================

# --- Initialization ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Runtime flags (defaults)
DRY_RUN=false
NO_RESTART=false
GUI_MODE=false
ROLLBACK_MODE=false
ROLLBACK_DIR=""
USE_CONKY=false
SELECTED_STEPS=()

# All available steps in execution order
ALL_STEPS=(deps wayland fstab repos fonts ags conky zsh plasma session)
DEFAULT_STEPS=(deps wayland fstab repos fonts ags zsh plasma session)

# Log file (unique per run, based on timestamp)
LOG_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/kde-tuning-${LOG_TIMESTAMP}.log"

# --- Logging ---

_log_raw() {
    echo -e "$*" | tee -a "$LOG_FILE"
}

error_exit() {
    if $GUI_MODE; then
        echo "[FAIL:fatal] $*" | tee -a "$LOG_FILE" >&2
    else
        echo -e "${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE" >&2
    fi
    exit 1
}

log_warn() {
    if $GUI_MODE; then
        echo "[WARN] $*" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}Warning: $*${NC}" | tee -a "$LOG_FILE"
    fi
}

log_step() {
    if $GUI_MODE; then
        echo "[STEP:start] $*" | tee -a "$LOG_FILE"
    else
        echo -e "${BLUE}==> $*${NC}" | tee -a "$LOG_FILE"
    fi
}

log_ok() {
    if $GUI_MODE; then
        echo "[STEP:ok] $*" | tee -a "$LOG_FILE"
    else
        echo -e "${GREEN}✓ $*${NC}" | tee -a "$LOG_FILE"
    fi
}

log_info() {
    if $GUI_MODE; then
        echo "[INFO] $*" | tee -a "$LOG_FILE"
    else
        echo -e "${BLUE}$*${NC}" | tee -a "$LOG_FILE"
    fi
}

log_progress() {
    local current="$1"
    local total="$2"
    local label="$3"
    if $GUI_MODE; then
        echo "[PROGRESS:${current}/${total}] ${label}" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}[${current}/${total}] ${label}${NC}" | tee -a "$LOG_FILE"
    fi
}

log_dry() {
    if $GUI_MODE; then
        echo "[DRY-RUN] $*" | tee -a "$LOG_FILE"
    else
        echo -e "${YELLOW}[DRY-RUN] $*${NC}" | tee -a "$LOG_FILE"
    fi
}

# --- Argument Parser ---

show_help() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
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
            --gui-mode)
                GUI_MODE=true
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

# --- User & Directory Setup ---

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

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- Helper Functions ---

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

# Safe copy/mkdir that respects --dry-run
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

preflight_checks() {
    log_step "Running preflight checks"

    ensure_cmd getent
    ensure_cmd cp
    ensure_cmd sed

    [ -n "$REAL_USER" ] || error_exit "REAL_USER is empty"
    [ -n "$REAL_HOME" ] || error_exit "REAL_HOME is empty"
    [ -d "$REAL_HOME" ] || error_exit "Home directory does not exist: $REAL_HOME"

    # Only check dirs/files needed for the selected steps
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

run_step() {
    local name="$1"
    shift
    "$@" || error_exit "Step failed: $name"
}

set_single_line() {
    local file_path="$1"
    local match_regex="$2"
    local desired_line="$3"

    if $DRY_RUN; then
        log_dry "set line matching '$match_regex' to '$desired_line' in $file_path"
        return 0
    fi

    local tmp_file
    mkdir -p "$(dirname "$file_path")"
    touch "$file_path"
    tmp_file="$(mktemp)"
    grep -Ev "$match_regex" "$file_path" > "$tmp_file" || true
    mv "$tmp_file" "$file_path"
    printf '%s\n' "$desired_line" >> "$file_path"
}

set_ini_key() {
    local file_path="$1"
    local section="$2"
    local key="$3"
    local value="$4"

    if $DRY_RUN; then
        log_dry "set [$section] $key=$value in $file_path"
        return 0
    fi

    local tmp_file
    mkdir -p "$(dirname "$file_path")"
    touch "$file_path"
    tmp_file="$(mktemp)"

    awk -v section="$section" -v key="$key" -v value="$value" '
        BEGIN {
            in_section = 0
            section_found = 0
            key_written = 0
        }

        /^\[.*\]$/ {
            if (in_section && !key_written) {
                print key "=" value
                key_written = 1
            }
            in_section = ($0 == "[" section "]")
            if (in_section) {
                section_found = 1
            }
            print
            next
        }

        {
            if (in_section && $0 ~ "^" key "=") {
                if (!key_written) {
                    print key "=" value
                    key_written = 1
                }
                next
            }
            print
        }

        END {
            if (in_section && !key_written) {
                print key "=" value
                key_written = 1
            }
            if (!section_found) {
                print ""
                print "[" section "]"
                print key "=" value
            }
        }
    ' "$file_path" > "$tmp_file"

    mv "$tmp_file" "$file_path"
}

clone_repo_if_missing() {
    local target_dir="$1"
    local repo_url="$2"
    local label="$3"
    shift 3
    local clone_args=("$@")

    if $DRY_RUN; then
        if [[ ! -d "$target_dir" ]]; then
            log_dry "git clone ${clone_args[*]} $repo_url $target_dir"
        else
            log_info "✓ $label already installed"
        fi
        return 0
    fi

    if [[ ! -d "$target_dir" ]]; then
        log_info "Cloning $label..."
        git clone "${clone_args[@]}" "$repo_url" "$target_dir"
    else
        log_ok "$label already installed"
    fi
}

# --- Main Tasks ---

install_dependencies() {
    log_progress "$1" "$2" "Installing system dependencies"

    ensure_cmd pacman

    PKGS=(
        "playerctl" "jq" "curl" "git" "zsh" "python" "fzf" "zoxide"
        "fastfetch" "lazygit" "git-delta" "lm_sensors"
        "wireless_tools" "ttf-hack-nerd" "imagemagick"
        "appmenu-gtk-module"
    )

    local want_ags=false
    local want_conky=false
    if step_is_selected "ags"; then want_ags=true; fi
    if step_is_selected "conky"; then want_conky=true; fi
    # If 'deps' was invoked standalone without widget steps, follow --conky flag
    if ! $want_ags && ! $want_conky; then
        if $USE_CONKY; then want_conky=true; else want_ags=true; fi
    fi

    if $want_ags; then
        PKGS+=("gjs" "gtk4-layer-shell")
    fi
    if $want_conky; then
        PKGS+=("conky")
    fi

    local AUR_PKGS=()
    if $want_ags; then
        # AGS v3 is available from the AUR (needs an AUR helper).
        AUR_PKGS+=("aylurs-gtk-shell")
    fi

    if (( ${#AUR_PKGS[@]} > 0 )) && command -v yay &> /dev/null; then
        INSTALL_CMD=(yay -S --needed --noconfirm)
        PKGS+=("${AUR_PKGS[@]}")
    else
        INSTALL_CMD=(run_as_root pacman -S --needed --noconfirm)
        if (( ${#AUR_PKGS[@]} > 0 )); then
            log_warn "yay not found: skipping AUR packages (${AUR_PKGS[*]}). Install them manually to use the AGS widget."
        fi
    fi

    if $DRY_RUN; then
        log_dry "Would install packages: ${PKGS[*]}"
    else
        log_info "Using command: ${INSTALL_CMD[*]}"
        "${INSTALL_CMD[@]}" "${PKGS[@]}"

        ensure_cmd git
        ensure_cmd zsh
        ensure_cmd python3
        if $want_ags; then
            command -v ags &> /dev/null || log_warn "ags is not installed (AUR: aylurs-gtk-shell); the widget will not start."
        fi
        ensure_cmd fc-cache
    fi

    log_ok "System dependencies done"
}

configure_wayland_touchpad() {
    local kcminput="$REAL_HOME/.config/kcminputrc"
    local kwrite_bin=""
    if command -v kwriteconfig6 &>/dev/null; then
        kwrite_bin="kwriteconfig6"
    elif command -v kwriteconfig5 &>/dev/null; then
        kwrite_bin="kwriteconfig5"
    fi

    local found=0
    local dev_dir
    for dev_dir in /sys/class/input/event*/device; do
        [[ -d "$dev_dir" ]] || continue
        local dev_name
        dev_name=$(cat "$dev_dir/name" 2>/dev/null || true)
        if [[ "${dev_name,,}" == *touchpad* ]]; then
            local vendor=$(( 16#$(cat "$dev_dir/id/vendor" 2>/dev/null || echo 0) ))
            local product=$(( 16#$(cat "$dev_dir/id/product" 2>/dev/null || echo 0) ))
            (( found++ )) || true
            if $DRY_RUN; then
                log_dry "Wayland touchpad [$vendor][$product][$dev_name]: TapToClick=true, NaturalScroll=true in $kcminput"
            elif [[ -n "$kwrite_bin" ]]; then
                "$kwrite_bin" --file "$kcminput" --group "Libinput" --group "$vendor" --group "$product" --group "$dev_name" --key "TapToClick" "true"
                "$kwrite_bin" --file "$kcminput" --group "Libinput" --group "$vendor" --group "$product" --group "$dev_name" --key "NaturalScroll" "true"
                log_ok "Wayland touchpad configured: $dev_name (TapToClick + NaturalScroll)"
            else
                log_warn "kwriteconfig6/kwriteconfig5 not found; skipping Wayland touchpad config in $kcminput"
            fi
        fi
    done

    if (( found == 0 )); then
        log_info "No touchpad device detected under /sys/class/input; skipping Wayland touchpad config."
    elif ! $DRY_RUN && command -v qdbus6 &>/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    fi
}

configure_wayland_session() {
    log_progress "$1" "$2" "Configuring Plasma Wayland session & touchpad"

    local sddm_session="plasma"
    local sddm_session_file="/usr/share/wayland-sessions/plasma.desktop"
    if [ ! -f "$sddm_session_file" ] && ! $DRY_RUN; then
        log_warn "Plasma Wayland session file not found ($sddm_session_file). SDDM config may not work until next reboot."
    fi

    local conf_dir="/etc/sddm.conf.d"
    local sddm_conf="$conf_dir/kde_settings.conf"
    local template_conf="$REPO_DIR/sddm/kde_settings.conf"

    if [ ! -f "$template_conf" ]; then
        echo -e "${RED}Missing SDDM template: $template_conf${NC}" >&2
        return 1
    fi

    if $DRY_RUN; then
        log_dry "mkdir -p $conf_dir"
        log_dry "cp $template_conf $sddm_conf"
        log_dry "sed -i 's/User=.*/User=$REAL_USER/' $sddm_conf"
        log_dry "set Session=$sddm_session in $sddm_conf"
        log_dry "write /var/lib/sddm/state.conf (Wayland)"
        log_dry "write /var/lib/sddm/.config/state.conf (Wayland)"
        log_dry "chown -R sddm:sddm /var/lib/sddm"
    else
        log_info "Copying SDDM Wayland template to $sddm_conf..."
        run_as_root mkdir -p "$conf_dir"
        run_as_root cp "$template_conf" "$sddm_conf"
        run_as_root sed -i -E "s|^User=.*$|User=$REAL_USER|" "$sddm_conf"
        run_as_root sed -i -E "s|^Session=.*$|Session=$sddm_session|" "$sddm_conf"

        for state_conf in /var/lib/sddm/state.conf /var/lib/sddm/.config/state.conf; do
            run_as_root mkdir -p "$(dirname "$state_conf")"
            run_as_root tee "$state_conf" > /dev/null <<EOF
[Last]
Session=${sddm_session_file}
User=$REAL_USER
EOF
        done
        run_as_root chown -R sddm:sddm /var/lib/sddm
    fi

    configure_wayland_touchpad

    log_ok "SDDM Plasma Wayland session & touchpad configured"
}

setup_fstab() {
    log_progress "$1" "$2" "Configuring storage volumes in /etc/fstab"

    # Target storage volumes: LABEL:MOUNTPOINT:FALLBACK_UUID
    local targets=(
        "Documentos:/documentos:6FFB75110F2D5860"
        "Juegos:/juegos:D8E8581CE857F6EA"
        "Personal:/personal:6F520EBC0641B2F4"
    )

    local user_uid
    local user_gid
    user_uid="$(id -u "$REAL_USER")"
    user_gid="$(id -g "$REAL_USER")"

    local fstab_file="/etc/fstab"
    local fstab_modified=false
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_file="/etc/fstab.bak-${timestamp}"

    ensure_file "$fstab_file"

    for entry in "${targets[@]}"; do
        IFS=':' read -r label mountpoint fallback_uuid <<< "$entry"

        local uuid=""
        local fstype=""
        local dev_node=""

        if command -v findfs &>/dev/null; then
            dev_node="$(findfs LABEL="$label" 2>/dev/null || true)"
        fi

        if [[ -n "$dev_node" ]]; then
            uuid="$(lsblk -no UUID "$dev_node" 2>/dev/null | head -1 || true)"
            fstype="$(lsblk -no FSTYPE "$dev_node" 2>/dev/null | head -1 || true)"
        fi

        # Fallback to UUID matching if label lookup yielded nothing
        if [[ -z "$uuid" && -n "$fallback_uuid" ]]; then
            if lsblk -no UUID 2>/dev/null | grep -qx "$fallback_uuid"; then
                uuid="$fallback_uuid"
                fstype="$(lsblk -rn -o UUID,FSTYPE 2>/dev/null | awk -v u="$uuid" '$1 == u {print $2; exit}')"
            fi
        fi

        if [[ -z "$uuid" ]]; then
            log_warn "Volume '$label' not detected on this system. Skipping."
            continue
        fi

        [[ -z "$fstype" ]] && fstype="ntfs"
        local mount_fs="$fstype"
        [[ "$fstype" == "ntfs3" ]] && mount_fs="ntfs"

        local mount_opts="defaults,nofail"
        if [[ "$mount_fs" == "ntfs" || "$mount_fs" == "vfat" || "$mount_fs" == "exfat" ]]; then
            mount_opts="defaults,nofail,uid=${user_uid},gid=${user_gid},x-systemd.device-timeout=10s"
        fi

        # Check if already in /etc/fstab by UUID or mount point
        if grep -qE "UUID=${uuid}" "$fstab_file" 2>/dev/null || awk -v m="$mountpoint" '$2 == m' "$fstab_file" 2>/dev/null | grep -q .; then
            log_ok "Mount $mountpoint (UUID=$uuid) already configured in $fstab_file"
            if $DRY_RUN; then
                log_dry "Ensure mount directory exists: $mountpoint"
            else
                if [[ ! -d "$mountpoint" ]]; then
                    run_as_root mkdir -p "$mountpoint"
                    run_as_root chown "${user_uid}:${user_gid}" "$mountpoint"
                fi
            fi
            continue
        fi

        local fstab_line="UUID=${uuid}  ${mountpoint}  ${mount_fs}  ${mount_opts}  0  0"

        if $DRY_RUN; then
            if ! $fstab_modified; then
                log_dry "Would backup $fstab_file to $backup_file"
                fstab_modified=true
            fi
            log_dry "Would create directory: $mountpoint"
            log_dry "Would add entry to $fstab_file: $fstab_line"
            log_dry "Would run: systemctl daemon-reload && mount $mountpoint"
        else
            if ! $fstab_modified; then
                log_info "Creating backup of $fstab_file at $backup_file..."
                run_as_root cp "$fstab_file" "$backup_file"
                run_as_root cp "$fstab_file" "/etc/fstab.bak"
                fstab_modified=true
            fi

            run_as_root mkdir -p "$mountpoint"
            run_as_root chown "${user_uid}:${user_gid}" "$mountpoint"

            log_info "Adding $label to $fstab_file ($mountpoint)..."
            printf '%s\n' "$fstab_line" | run_as_root tee -a "$fstab_file" > /dev/null

            log_ok "Added $label ($mountpoint) to $fstab_file"
        fi
    done

    if ! $DRY_RUN && $fstab_modified; then
        log_info "Reloading systemd daemon to recognize new mount points..."
        run_as_root systemctl daemon-reload

        for entry in "${targets[@]}"; do
            IFS=':' read -r label mountpoint fallback_uuid <<< "$entry"
            if grep -q " ${mountpoint} " "$fstab_file" 2>/dev/null; then
                if ! findmnt -M "$mountpoint" &>/dev/null; then
                    local current_run_media="/run/media/${REAL_USER}/${label}"
                    if findmnt -M "$current_run_media" &>/dev/null; then
                        log_info "Unmounting temporary mount at $current_run_media..."
                        run_as_root umount "$current_run_media" 2>/dev/null || log_warn "Could not unmount $current_run_media (may be in use)."
                    fi

                    if run_as_root mount "$mountpoint" 2>/dev/null; then
                        log_ok "Successfully mounted $mountpoint"
                    else
                        log_warn "Could not mount $mountpoint immediately (device may be busy). It will mount automatically on next reboot."
                    fi
                else
                    log_ok "$mountpoint is already mounted"
                fi
            fi
        done
    fi

    log_ok "fstab configuration completed"
}

install_external_repos() {
    log_progress "$1" "$2" "Checking external repositories"

    clone_repo_if_missing "$REAL_HOME/powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "Powerlevel10k" --depth=1

    dry_mkdir "$REAL_HOME/.zsh-plugins"
    clone_repo_if_missing "$REAL_HOME/.zsh-plugins/zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions" "zsh-autosuggestions"
    clone_repo_if_missing "$REAL_HOME/.zsh-plugins/zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" "zsh-syntax-highlighting"

    if $DRY_RUN; then
        log_dry "Would clone and install Orchis KDE theme (if missing)"
        log_dry "Would clone and install Tela Circle icon theme (if missing)"
        log_dry "Would clone and install Vimix cursors (if missing)"
    else
        if [[ ! -d "$REAL_HOME/Orchis-kde" ]]; then
            log_info "Cloning Orchis KDE theme..."
            git clone https://github.com/vinceliuice/Orchis-kde.git "$REAL_HOME/Orchis-kde"
            log_info "Installing Orchis theme..."
            "$REAL_HOME/Orchis-kde/install.sh"
        else
            log_ok "Orchis KDE theme already installed"
        fi

        # Patch known upstream bug in Orchis-dark tooltip.svgz (accidental #fefefe white background)
        local orchis_theme_dir="$REAL_HOME/.local/share/plasma/desktoptheme/Orchis-dark"
        if [[ -d "$orchis_theme_dir" ]]; then
            for t_file in "$orchis_theme_dir/widgets/tooltip.svgz" \
                          "$orchis_theme_dir/translucent/widgets/tooltip.svgz" \
                          "$orchis_theme_dir/solid/widgets/tooltip.svgz"; do
                if [[ -f "$t_file" ]] && gzip -dc "$t_file" 2>/dev/null | grep -q "color:#fefefe"; then
                    gzip -dc "$t_file" | sed -e 's/#fefefe/#282828/g' -e 's/#333333/#dfdfdf/g' | gzip -cn9 > "$t_file.tmp"
                    mv "$t_file.tmp" "$t_file"
                fi
            done
        fi

        if [[ ! -d "$REAL_HOME/tela-circle-icon-theme" ]]; then
            log_info "Cloning Tela Circle icon theme..."
            git clone https://github.com/vinceliuice/tela-circle-icon-theme.git "$REAL_HOME/tela-circle-icon-theme"
            log_info "Installing Tela Circle icons..."
            "$REAL_HOME/tela-circle-icon-theme/install.sh" -a
        else
            log_ok "Tela Circle icon theme already installed"
        fi

        if [[ ! -d "$REAL_HOME/Vimix-cursors" ]]; then
            log_info "Cloning Vimix cursors theme..."
            git clone https://github.com/vinceliuice/Vimix-cursors.git "$REAL_HOME/Vimix-cursors"
            log_info "Installing Vimix cursors..."
            (cd "$REAL_HOME/Vimix-cursors" && HOME="$REAL_HOME" bash install.sh)
        else
            log_ok "Vimix cursors already installed"
        fi
    fi

    log_ok "External repositories setup complete"
}

install_fonts() {
    log_progress "$1" "$2" "Installing fonts"
    dry_mkdir "$REAL_HOME/.local/share/fonts"
    ensure_file "$REPO_DIR/ags/fonts/Abel-Regular.ttf"

    if $DRY_RUN; then
        log_dry "cp *.ttf $REAL_HOME/.local/share/fonts/"
        log_dry "fc-cache -fv"
    else
        if ! compgen -G "$REPO_DIR/ags/fonts/*.ttf" > /dev/null; then
            error_exit "No .ttf files found in $REPO_DIR/ags/fonts"
        fi

        cp "$REPO_DIR"/ags/fonts/*.ttf "$REAL_HOME/.local/share/fonts/"
        fc-cache -fv > /dev/null
    fi

    log_ok "Fonts installed"
}

setup_conky() {
    log_progress "$1" "$2" "Setting up Conky Mimosa (Right Side)"
    ensure_dir "$REPO_DIR/conky/Mimosa"
    ensure_file "$REPO_DIR/conky/conky-mimosa.desktop"

    dry_mkdir "$REAL_HOME/.config/conky"
    if $DRY_RUN; then
        log_dry "cp -r $REPO_DIR/conky/Mimosa $REAL_HOME/.config/conky/"
        log_dry "chmod +x .config/conky/Mimosa/start.sh + scripts/*"
        log_dry "Run hardware auto-detection (.config/conky/Mimosa/scripts/hw-detect.sh)"
        log_dry "cp conky-mimosa.desktop $REAL_HOME/.config/autostart/"
        log_dry "Set Exec path in $REAL_HOME/.config/autostart/conky-mimosa.desktop"
        log_dry "Would restart Conky if currently running"
    else
        cp -r "$REPO_DIR"/conky/Mimosa "$REAL_HOME/.config/conky/"
        chmod +x "$REAL_HOME/.config/conky/Mimosa/start.sh"
        chmod +x "$REAL_HOME/.config/conky/Mimosa/scripts"/*
        if [[ -x "$REAL_HOME/.config/conky/Mimosa/scripts/hw-detect.sh" ]]; then
            log_info "Detecting hardware profile for Conky..."
            "$REAL_HOME/.config/conky/Mimosa/scripts/hw-detect.sh" || log_warn "Hardware auto-detection reported a non-fatal warning"
        fi
        mkdir -p "$REAL_HOME/.config/autostart"
        cp "$REPO_DIR"/conky/conky-mimosa.desktop "$REAL_HOME/.config/autostart/"
        sed -i -E "s|^Exec=.*|Exec=${REAL_HOME}/.config/conky/Mimosa/start.sh|" "$REAL_HOME/.config/autostart/conky-mimosa.desktop"

        if command -v systemctl &>/dev/null; then
            systemctl --user daemon-reload 2>/dev/null || true
        fi

        # Initialize cover art cache if missing
        if [[ ! -f /tmp/conky_cover.png && -f "$REAL_HOME/.config/conky/Mimosa/assets/default_cover.png" ]]; then
            cp "$REAL_HOME/.config/conky/Mimosa/assets/default_cover.png" /tmp/conky_cover.png
        fi

        # If AGS was not also explicitly selected, remove its autostart and stop it
        if ! step_is_selected "ags"; then
            rm -f "$REAL_HOME/.config/autostart/mimosa-ags.desktop"
            ags quit -i mimosa &> /dev/null || true
            pkill -f "ags run .*/mimosa-ags/app.tsx" 2>/dev/null || true
        fi

        # Stop any stale instances
        pkill -9 -x conky 2>/dev/null || true
        sleep 1

        # Launch Conky if an active display is present
        if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            log_info "Starting Conky Mimosa..."
            if [[ -x "$REAL_HOME/.config/conky/Mimosa/start.sh" ]]; then
                "$REAL_HOME/.config/conky/Mimosa/start.sh"
            fi
        else
            log_info "No display detected; Conky will autostart upon graphical login."
        fi
    fi

    log_ok "Conky setup complete"
}

setup_ags() {
    log_progress "$1" "$2" "Setting up Mimosa AGS widget (Left Side)"
    ensure_dir "$REPO_DIR/ags"
    ensure_file "$REPO_DIR/ags/mimosa-ags.desktop"
    ensure_file "$REPO_DIR/ags/app.tsx"

    local dest="$REAL_HOME/.config/mimosa-ags"

    if $DRY_RUN; then
        log_dry "mkdir -p $dest && cp -rT $REPO_DIR/ags $dest"
        log_dry "chmod +x $dest/start.sh + scripts/*"
        log_dry "cp mimosa-ags.desktop $REAL_HOME/.config/autostart/"
        log_dry "Set Exec path in $REAL_HOME/.config/autostart/mimosa-ags.desktop"
        log_dry "Would (re)start the widget if running inside a Wayland session"
        log_ok "AGS widget setup (dry-run)"
        return 0
    fi

    mkdir -p "$dest" "$REAL_HOME/.config/autostart"
    cp -rT "$REPO_DIR/ags" "$dest"
    chmod +x "$dest/start.sh" "$dest"/scripts/*

    cp "$REPO_DIR/ags/mimosa-ags.desktop" "$REAL_HOME/.config/autostart/"
    sed -i -E "s|^Exec=.*|Exec=${dest}/start.sh|" "$REAL_HOME/.config/autostart/mimosa-ags.desktop"

    # If Conky was not also explicitly selected, remove its autostart and stop it
    if ! step_is_selected "conky"; then
        rm -f "$REAL_HOME/.config/autostart/conky-mimosa.desktop"
        pkill -9 -x conky 2>/dev/null || true
    fi

    if ! command -v ags &> /dev/null; then
        log_warn "ags not found. Install aylurs-gtk-shell from the AUR and re-run."
    elif [[ "${XDG_SESSION_TYPE:-}" != "wayland" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        log_info "Not in a Wayland session; the widget will start at your next Plasma (Wayland) login."
    else
        log_info "Starting Mimosa AGS widget..."
        "$dest/start.sh" || log_warn "start.sh reported a non-fatal warning"
    fi

    log_ok "AGS widget setup complete"
}

setup_zsh() {
    log_progress "$1" "$2" "Applying Zsh & Powerlevel10k config"
    ensure_file "$REPO_DIR/zsh/.zshrc"
    ensure_file "$REPO_DIR/zsh/.p10k.zsh"

    if $DRY_RUN; then
        log_dry "backup + cp .zshrc and .p10k.zsh to $REAL_HOME"
    else
        [[ -f "$REAL_HOME/.zshrc" ]] && cp "$REAL_HOME/.zshrc" "$REAL_HOME/.zshrc.bak"
        [[ -f "$REAL_HOME/.p10k.zsh" ]] && cp "$REAL_HOME/.p10k.zsh" "$REAL_HOME/.p10k.zsh.bak"
        cp "$REPO_DIR"/zsh/.zshrc "$REAL_HOME/.zshrc"
        cp "$REPO_DIR"/zsh/.p10k.zsh "$REAL_HOME/.p10k.zsh"
    fi

    log_ok "Zsh configuration applied"
}

restore_plasma_config() {
    log_progress "$1" "$2" "Restoring KDE Plasma configuration"
    local plasma_files=(
        "plasmarc" "plasma-org.kde.plasma.desktop-appletsrc" "plasmashellrc"
        "kglobalshortcutsrc" "kwinrc" "kdeglobals" "kactivitymanagerdrc"
    )

    local backup_dir="$REAL_HOME/.config/kde_backup_$(date +%Y%m%d_%H%M%S_%N)"

    if $DRY_RUN; then
        log_dry "Would create backup dir: $backup_dir"
        for file in "${plasma_files[@]}"; do
            log_dry "Would backup + restore: $file"
        done
        log_dry "Would set Plasma desktop theme to dark (breeze-dark or breath-dark)"
        log_dry "Would set Vimix cursor theme in kdeglobals, kcminputrc, Xresources, xprofile, gtkrc, gtk-3.0, gtk-4.0"
        log_ok "KDE Plasma settings (dry-run)"
        return 0
    fi

    mkdir -p "$backup_dir"

    for file in "${plasma_files[@]}"; do
        ensure_file "$REPO_DIR/plasma/$file"
        [[ -f "$REAL_HOME/.config/$file" ]] && cp "$REAL_HOME/.config/$file" "$backup_dir"/
        cp "$REPO_DIR"/plasma/"$file" "$REAL_HOME/.config/$file"
    done

    # Record which backup was created so rollback can find the latest
    echo "$backup_dir" > "$REAL_HOME/.config/.kde_last_backup"

    # Ensure a fully compatible native Plasma 6 dark SVG theme for panels, tooltips and widgets
    # Third-party themes like Orchis-dark (Plasma 5 API) cause illegible light tooltips in Plasma 6
    local plasma_theme="breeze-dark"
    if [[ ! -d "/usr/share/plasma/desktoptheme/breeze-dark" && -d "/usr/share/plasma/desktoptheme/breath-dark" ]]; then
        plasma_theme="breath-dark"
    fi

    # Set theme configuration in plasmarc, kdeglobals and kcminputrc
    local kwrite
    if command -v kwriteconfig6 &> /dev/null; then
        kwrite="kwriteconfig6"
    elif command -v kwriteconfig5 &> /dev/null; then
        kwrite="kwriteconfig5"
    else
        kwrite=""
    fi

    if [[ -n "$kwrite" ]]; then
        "$kwrite" --file "$REAL_HOME/.config/plasmarc" --group Theme --key name "$plasma_theme"
        "$kwrite" --file "$REAL_HOME/.config/kdeglobals"  --group Icons --key cursorTheme "Vimix-cursors"
        "$kwrite" --file "$REAL_HOME/.config/kcminputrc"  --group Mouse --key cursorTheme "Vimix-cursors"

        # Fallback LookAndFeelPackage if Orchis is not installed
        if [[ ! -d "/usr/share/plasma/look-and-feel/com.github.vinceliuice.Orchis-dark" && ! -d "$REAL_HOME/.local/share/plasma/look-and-feel/com.github.vinceliuice.Orchis-dark" ]]; then
            local fallback_lnf="org.kde.breezedark.desktop"
            [[ -d "/usr/share/plasma/look-and-feel/org.manjaro.breath-dark.desktop" ]] && fallback_lnf="org.manjaro.breath-dark.desktop"
            "$kwrite" --file "$REAL_HOME/.config/kdeglobals" --group KDE --key LookAndFeelPackage "$fallback_lnf"
        fi

        log_ok "Plasma desktop theme set to $plasma_theme"
        log_ok "Cursor theme set to Vimix-cursors"
    else
        mkdir -p "$REAL_HOME/.config"
        set_ini_key "$REAL_HOME/.config/plasmarc" "Theme" "name" "$plasma_theme"
        if grep -q "^\[Icons\]" "$REAL_HOME/.config/kdeglobals" 2>/dev/null; then
            sed -i '/^\[Icons\]/,/^\[/{s/^cursorTheme=.*/cursorTheme=Vimix-cursors/}' "$REAL_HOME/.config/kdeglobals"
        else
            printf '\n[Icons]\ncursorTheme=Vimix-cursors\n' >> "$REAL_HOME/.config/kdeglobals"
        fi
        if grep -q "^\[Mouse\]" "$REAL_HOME/.config/kcminputrc" 2>/dev/null; then
            sed -i '/^\[Mouse\]/,/^\[/{s/^cursorTheme=.*/cursorTheme=Vimix-cursors/}' "$REAL_HOME/.config/kcminputrc"
        else
            printf '\n[Mouse]\ncursorTheme=Vimix-cursors\n' >> "$REAL_HOME/.config/kcminputrc"
        fi
        log_ok "Plasma desktop theme and cursors set (fallback method)"
    fi

    mkdir -p "$REAL_HOME/.icons/default"
    cat > "$REAL_HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=Vimix-cursors
EOF

    set_single_line "$REAL_HOME/.Xresources" '^Xcursor\.theme:' 'Xcursor.theme: Vimix-cursors'
    set_single_line "$REAL_HOME/.Xresources" '^Xcursor\.size:' 'Xcursor.size: 24'

    set_single_line "$REAL_HOME/.xprofile" '^export XCURSOR_THEME=' 'export XCURSOR_THEME=Vimix-cursors'
    set_single_line "$REAL_HOME/.xprofile" '^export XCURSOR_SIZE=' 'export XCURSOR_SIZE=24'

    mkdir -p "$REAL_HOME/.config"
    set_single_line "$REAL_HOME/.gtkrc-2.0" '^gtk-cursor-theme-name=' 'gtk-cursor-theme-name="Vimix-cursors"'
    set_single_line "$REAL_HOME/.gtkrc-2.0" '^gtk-cursor-theme-size=' 'gtk-cursor-theme-size=24'

    mkdir -p "$REAL_HOME/.config/gtk-3.0"
    set_ini_key "$REAL_HOME/.config/gtk-3.0/settings.ini" "Settings" "gtk-cursor-theme-name" "Vimix-cursors"
    set_ini_key "$REAL_HOME/.config/gtk-3.0/settings.ini" "Settings" "gtk-cursor-theme-size" "24"

    mkdir -p "$REAL_HOME/.config/gtk-4.0"
    set_ini_key "$REAL_HOME/.config/gtk-4.0/settings.ini" "Settings" "gtk-cursor-theme-name" "Vimix-cursors"
    set_ini_key "$REAL_HOME/.config/gtk-4.0/settings.ini" "Settings" "gtk-cursor-theme-size" "24"

    log_ok "X11 cursor theme configured (X11, GTK2/3/4, session env)"
    log_ok "KDE Plasma settings restored (backup: $backup_dir)"
}

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

# --- Rollback ---

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

# --- Step Dispatcher ---

step_is_selected() {
    local step="$1"
    for s in "${SELECTED_STEPS[@]}"; do
        [[ "$s" == "$step" ]] && return 0
    done
    return 1
}

# --- Execution ---

parse_args "$@"

log_info "Log file: $LOG_FILE"
log_info "Running as user: $REAL_USER (home: $REAL_HOME)"

if $DRY_RUN; then
    log_warn "DRY-RUN mode: no system changes will be made."
fi

if $ROLLBACK_MODE; then
    do_rollback
    exit 0
fi

preflight_checks

# Only request sudo if a step that needs it is selected
if step_is_selected "deps" || step_is_selected "wayland" || step_is_selected "fstab"; then
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
