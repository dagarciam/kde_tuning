#!/bin/bash

set -Eeuo pipefail

# ==============================================================================
# KDE Tuning - Master Setup Script
# Author: dagarciam
# Description: Automates the deployment of Conky, Zsh, and KDE configurations.
# Usage:
#   ./setup.sh [OPTIONS]
#
# Options:
#   --steps <list>     Comma-separated list of steps to run.
#                      Steps: deps,x11,repos,fonts,conky,zsh,plasma,session
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
SELECTED_STEPS=()

# All available steps in execution order
ALL_STEPS=(deps x11 repos fonts conky zsh plasma session)

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

    # Validate --steps values
    for step in "${SELECTED_STEPS[@]}"; do
        local valid=false
        for s in "${ALL_STEPS[@]}"; do
            [[ "$step" == "$s" ]] && valid=true && break
        done
        $valid || error_exit "Unknown step: '$step'. Valid steps: ${ALL_STEPS[*]}"
    done

    # Validate --rollback combinations
    if $ROLLBACK_MODE; then
        for step in "${SELECTED_STEPS[@]}"; do
            [[ "$step" == "plasma" ]] && error_exit "--rollback cannot be combined with --steps containing 'plasma' (conflicting write/restore)."
        done
    fi

    # Default: run all steps
    if [[ ${#SELECTED_STEPS[@]} -eq 0 ]] && ! $ROLLBACK_MODE; then
        SELECTED_STEPS=("${ALL_STEPS[@]}")
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

detect_x11_package() {
    local candidates=("plasma-x11-session" "plasma-workspace-x11")
    local pkg

    for pkg in "${candidates[@]}"; do
        if pacman -Si "$pkg" &> /dev/null; then
            echo "$pkg"
            return 0
        fi
    done

    return 1
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
    local check_all=false
    local steps_needing_files=(deps repos fonts conky zsh plasma)
    for step in "${SELECTED_STEPS[@]}"; do
        for needs in "${steps_needing_files[@]}"; do
            [[ "$step" == "$needs" ]] && check_all=true && break 2
        done
    done

    if $check_all || [[ ${#SELECTED_STEPS[@]} -eq ${#ALL_STEPS[@]} ]]; then
        ensure_dir "$REPO_DIR/conky/Mimosa"
        ensure_dir "$REPO_DIR/conky/Mimosa/fonts"
        ensure_dir "$REPO_DIR/plasma"
        ensure_dir "$REPO_DIR/zsh"
        ensure_dir "$REPO_DIR/sddm"

        ensure_file "$REPO_DIR/sddm/kde_settings.conf"
        ensure_file "$REPO_DIR/conky/conky-mimosa.desktop"
        ensure_file "$REPO_DIR/zsh/.zshrc"
        ensure_file "$REPO_DIR/zsh/.p10k.zsh"
        ensure_file "$REPO_DIR/conky/Mimosa/fonts/Abel.zip"
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
        "conky" "playerctl" "jq" "curl" "git" "zsh" "python" "fzf" "zoxide"
        "fastfetch" "lazygit" "git-delta" "lm_sensors"
        "wireless_tools"
    )

    local x11_pkg
    if x11_pkg="$(detect_x11_package)"; then
        PKGS+=("$x11_pkg")
    else
        log_warn "No known Plasma X11 package found in repos (checked: plasma-x11-session, plasma-workspace-x11)."
    fi

    if command -v yay &> /dev/null; then
        INSTALL_CMD=(yay -S --needed --noconfirm)
    else
        INSTALL_CMD=(run_as_root pacman -S --needed --noconfirm)
    fi

    if $DRY_RUN; then
        log_dry "Would install packages: ${PKGS[*]}"
    else
        log_info "Using command: ${INSTALL_CMD[*]}"
        "${INSTALL_CMD[@]}" "${PKGS[@]}"

        ensure_cmd git
        ensure_cmd zsh
        ensure_cmd python3
        ensure_cmd conky
        ensure_cmd fc-cache
    fi

    log_ok "System dependencies done"
}

configure_x11_session() {
    log_progress "$1" "$2" "Configuring Plasma X11 as default session"

    if [ ! -f /usr/share/xsessions/plasmax11.desktop ] && ! $DRY_RUN; then
        log_warn "plasmax11.desktop not found. SDDM config may not work until next reboot."
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
        log_dry "write /var/lib/sddm/state.conf"
        log_dry "write /var/lib/sddm/.config/state.conf"
    else
        log_info "Copying SDDM template to $sddm_conf..."
        run_as_root mkdir -p "$conf_dir"
        run_as_root cp "$template_conf" "$sddm_conf"
        run_as_root sed -i -E "s|^User=.*$|User=$REAL_USER|" "$sddm_conf"

        for state_conf in /var/lib/sddm/state.conf /var/lib/sddm/.config/state.conf; do
            run_as_root mkdir -p "$(dirname "$state_conf")"
            run_as_root tee "$state_conf" > /dev/null <<EOF
[Last]
Session=plasmax11
User=$REAL_USER
EOF
        done
    fi

    log_ok "SDDM configured for Plasma X11"
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
    ensure_file "$REPO_DIR/conky/Mimosa/fonts/Abel.zip"

    if $DRY_RUN; then
        log_dry "cp *.ttf $REAL_HOME/.local/share/fonts/"
        log_dry "python3 -m zipfile -e Abel.zip $REAL_HOME/.local/share/fonts/"
        log_dry "fc-cache -fv"
    else
        if ! compgen -G "$REPO_DIR/conky/Mimosa/fonts/*.ttf" > /dev/null; then
            error_exit "No .ttf files found in $REPO_DIR/conky/Mimosa/fonts"
        fi

        cp "$REPO_DIR"/conky/Mimosa/fonts/*.ttf "$REAL_HOME/.local/share/fonts/"
        python3 -m zipfile -e "$REPO_DIR"/conky/Mimosa/fonts/Abel.zip "$REAL_HOME/.local/share/fonts/"
        fc-cache -fv > /dev/null
    fi

    log_ok "Fonts installed"
}

setup_conky() {
    log_progress "$1" "$2" "Setting up Conky Mimosa"
    ensure_dir "$REPO_DIR/conky/Mimosa"
    ensure_file "$REPO_DIR/conky/conky-mimosa.desktop"

    dry_mkdir "$REAL_HOME/.config/conky"
    if $DRY_RUN; then
        log_dry "cp -r $REPO_DIR/conky/Mimosa $REAL_HOME/.config/conky/"
        log_dry "chmod +x .config/conky/Mimosa/start.sh + scripts/*"
        log_dry "cp conky-mimosa.desktop $REAL_HOME/.config/autostart/"
    else
        cp -r "$REPO_DIR"/conky/Mimosa "$REAL_HOME/.config/conky/"
        chmod +x "$REAL_HOME/.config/conky/Mimosa/start.sh"
        chmod +x "$REAL_HOME/.config/conky/Mimosa/scripts"/*
        mkdir -p "$REAL_HOME/.config/autostart"
        cp "$REPO_DIR"/conky/conky-mimosa.desktop "$REAL_HOME/.config/autostart/"
    fi

    log_ok "Conky setup complete"
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
        "plasma-org.kde.plasma.desktop-appletsrc" "plasmashellrc"
        "kglobalshortcutsrc" "kwinrc" "kdeglobals" "kactivitymanagerdrc"
    )

    local backup_dir="$REAL_HOME/.config/kde_backup_$(date +%Y%m%d_%H%M%S_%N)"

    if $DRY_RUN; then
        log_dry "Would create backup dir: $backup_dir"
        for file in "${plasma_files[@]}"; do
            log_dry "Would backup + restore: $file"
        done
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

    # Set Vimix cursor theme in kdeglobals and kcminputrc
    local kwrite
    if command -v kwriteconfig6 &> /dev/null; then
        kwrite="kwriteconfig6"
    elif command -v kwriteconfig5 &> /dev/null; then
        kwrite="kwriteconfig5"
    else
        kwrite=""
    fi

    if [[ -n "$kwrite" ]]; then
        "$kwrite" --file "$REAL_HOME/.config/kdeglobals"  --group Icons --key cursorTheme "Vimix-cursors"
        "$kwrite" --file "$REAL_HOME/.config/kcminputrc"  --group Mouse --key cursorTheme "Vimix-cursors"
        log_ok "Cursor theme set to Vimix-cursors"
    else
        mkdir -p "$REAL_HOME/.config"
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
        log_ok "Cursor theme set to Vimix-cursors (fallback method)"
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
        log_warn "You are currently on Wayland. Reboot to use Plasma X11."
        log_info "SDDM is already configured for Plasma X11."
    else
        log_info "You are on X11. Restarting Plasma Shell..."
        pkill plasmashell 2>/dev/null || true
        sleep 1
        if command -v kstart6 &> /dev/null; then
            kstart6 plasmashell > /dev/null 2>&1 || true
        elif command -v kstart5 &> /dev/null; then
            kstart5 plasmashell > /dev/null 2>&1 || true
        else
            nohup plasmashell > /dev/null 2>&1 &
        fi
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
if step_is_selected "deps" || step_is_selected "x11"; then
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
            deps)    run_step "Install dependencies"         install_dependencies    "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            x11)     run_step "Configure X11 session"        configure_x11_session   "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            repos)   run_step "Install external repos"       install_external_repos  "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            fonts)   run_step "Install fonts"                install_fonts           "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            conky)   run_step "Setup Conky"                  setup_conky             "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            zsh)     run_step "Setup Zsh"                    setup_zsh               "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            plasma)  run_step "Restore Plasma config"        restore_plasma_config   "$CURRENT_STEP" "$TOTAL_STEPS" ;;
            session) run_step "Apply session changes"        apply_session_changes   "$CURRENT_STEP" "$TOTAL_STEPS" ;;
        esac
    fi
done

if $DRY_RUN; then
    log_ok "Dry-run complete. No changes were made."
else
    log_ok "Setup finished! Please restart your session if you didn't logout already."
fi
