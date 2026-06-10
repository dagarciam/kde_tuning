#!/bin/bash

# ==============================================================================
# KDE Tuning - Master Setup Script (Refactored)
# Author: dagarciam
# Description: Automates the deployment of Conky, Zsh, and KDE configurations.
# ==============================================================================

# --- Initialization ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Capture the real user and home directory BEFORE any sudo interactions
if [ "$EUID" -eq 0 ]; then
    # Script invoked with sudo; use SUDO_USER to get the real user
    REAL_USER="${SUDO_USER:-root}"
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
else
    # Script invoked as regular user
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

echo -e "${BLUE}Running as user: $REAL_USER (home: $REAL_HOME)${NC}"

# --- Helper Functions ---

# Keep sudo timestamp fresh while the script runs.
keep_sudo_alive() {
    while true; do
        if ! sudo -n true 2>/dev/null; then
            # sudo failed or needs password; stop attempting
            break
        fi
        sleep 50
        kill -0 "$$" || exit
    done &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

run_as_root() {
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

clone_repo_if_missing() {
    local target_dir="$1"
    local repo_url="$2"
    local label="$3"
    shift 3
    local clone_args=("$@")

    if [[ ! -d "$target_dir" ]]; then
        echo -e "${BLUE}Cloning $label...${NC}"
        git clone "${clone_args[@]}" "$repo_url" "$target_dir"
    else
        echo -e "${GREEN}✓ $label already installed${NC}"
    fi
}

# --- Main Tasks ---

install_dependencies() {
    echo -e "${YELLOW}[1/8] Installing system dependencies...${NC}"
    
    PKGS=(
        "conky" "playerctl" "jq" "curl" "git" "zsh" "python" "fzf" "zoxide"
        "fastfetch" "lazygit" "git-delta" "plasma-workspace-x11" "lm_sensors"
        "wireless_tools"
    )

    if command -v yay &> /dev/null; then
        INSTALL_CMD=(yay -S --needed --noconfirm)
    else
        INSTALL_CMD=(run_as_root pacman -S --needed --noconfirm)
    fi

    echo -e "Using command: ${BLUE}${INSTALL_CMD[*]}${NC}"
    "${INSTALL_CMD[@]}" "${PKGS[@]}"
}

configure_x11_session() {
    echo -e "${YELLOW}[2/8] Configuring Plasma X11 as default session...${NC}"

    if [ ! -f /usr/share/xsessions/plasmax11.desktop ]; then
        echo -e "${YELLOW}Warning: plasmax11.desktop not found after installation. SDDM config may not work until next reboot.${NC}"
    fi

    local conf_dir="/etc/sddm.conf.d"
    local sddm_conf="$conf_dir/kde_settings.conf"
    local template_conf="$REPO_DIR/sddm/kde_settings.conf"

    if [ ! -f "$template_conf" ]; then
        echo -e "${RED}Missing SDDM template: $template_conf${NC}"
        return 1
    fi

    echo -e "${BLUE}Copying SDDM template to $sddm_conf...${NC}"
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

    echo -e "${GREEN}SDDM configured for Plasma X11.${NC}"
}

install_external_repos() {
    echo -e "${YELLOW}[3/8] Checking external repositories...${NC}"

    clone_repo_if_missing "$REAL_HOME/powerlevel10k" "https://github.com/romkatv/powerlevel10k.git" "Powerlevel10k" --depth=1

    mkdir -p "$REAL_HOME/.zsh-plugins"
    clone_repo_if_missing "$REAL_HOME/.zsh-plugins/zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions" "zsh-autosuggestions"
    clone_repo_if_missing "$REAL_HOME/.zsh-plugins/zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git" "zsh-syntax-highlighting"

    if [[ ! -d "$REAL_HOME/Orchis-kde" ]]; then
        echo -e "${BLUE}Cloning Orchis KDE theme...${NC}"
        git clone https://github.com/vinceliuice/Orchis-kde.git "$REAL_HOME/Orchis-kde"
        echo -e "${BLUE}Installing Orchis theme...${NC}"
        "$REAL_HOME/Orchis-kde/install.sh"
    else
        echo -e "${GREEN}✓ Orchis KDE theme already installed${NC}"
    fi

    if [[ ! -d "$REAL_HOME/tela-circle-icon-theme" ]]; then
        echo -e "${BLUE}Cloning Tela Circle icon theme...${NC}"
        git clone https://github.com/vinceliuice/tela-circle-icon-theme.git "$REAL_HOME/tela-circle-icon-theme"
        echo -e "${BLUE}Installing Tela Circle icons...${NC}"
        "$REAL_HOME/tela-circle-icon-theme/install.sh" -a
    else
        echo -e "${GREEN}✓ Tela Circle icon theme already installed${NC}"
    fi

    if [[ ! -d "$REAL_HOME/Vimix-cursors" ]]; then
        echo -e "${BLUE}Cloning Vimix cursors theme...${NC}"
        git clone https://github.com/vinceliuice/Vimix-cursors.git "$REAL_HOME/Vimix-cursors"
        echo -e "${BLUE}Installing Vimix cursors...${NC}"
        (cd "$REAL_HOME/Vimix-cursors" && HOME="$REAL_HOME" bash install.sh)
    else
        echo -e "${GREEN}✓ Vimix cursors already installed${NC}"
    fi

    echo -e "${GREEN}External repositories setup complete.${NC}"
}

install_fonts() {
    echo -e "${YELLOW}[4/8] Installing fonts...${NC}"
    mkdir -p "$REAL_HOME/.local/share/fonts"
    cp "$REPO_DIR"/conky/Mimosa/fonts/*.ttf "$REAL_HOME/.local/share/fonts/"
    python3 -m zipfile -e "$REPO_DIR"/conky/Mimosa/fonts/Abel.zip "$REAL_HOME/.local/share/fonts/"
    fc-cache -fv > /dev/null
    echo -e "${GREEN}Fonts installed successfully.${NC}"
}

setup_conky() {
    echo -e "${YELLOW}[5/8] Setting up Conky Mimosa...${NC}"
    mkdir -p "$REAL_HOME/.config/conky"
    cp -r "$REPO_DIR"/conky/Mimosa "$REAL_HOME/.config/conky/"
    chmod +x "$REAL_HOME/.config/conky/Mimosa/start.sh"
    chmod +x "$REAL_HOME/.config/conky/Mimosa/scripts"/*

    mkdir -p "$REAL_HOME/.config/autostart"
    cp "$REPO_DIR"/conky/conky-mimosa.desktop "$REAL_HOME/.config/autostart/"
    echo -e "${GREEN}Conky setup complete.${NC}"
}

setup_zsh() {
    echo -e "${YELLOW}[6/8] Applying Zsh & Powerlevel10k config...${NC}"
    [[ -f "$REAL_HOME/.zshrc" ]] && cp "$REAL_HOME/.zshrc" "$REAL_HOME/.zshrc.bak"
    [[ -f "$REAL_HOME/.p10k.zsh" ]] && cp "$REAL_HOME/.p10k.zsh" "$REAL_HOME/.p10k.zsh.bak"

    cp "$REPO_DIR"/zsh/.zshrc "$REAL_HOME/.zshrc"
    cp "$REPO_DIR"/zsh/.p10k.zsh "$REAL_HOME/.p10k.zsh"
    echo -e "${GREEN}Zsh configuration applied.${NC}"
}

restore_plasma_config() {
    echo -e "${YELLOW}[7/8] Restoring KDE Plasma configuration...${NC}"
    PLASMA_FILES=(
        "plasma-org.kde.plasma.desktop-appletsrc" "plasmashellrc"
        "kglobalshortcutsrc" "kwinrc" "kdeglobals" "kactivitymanagerdrc"
    )

    BACKUP_DIR="$REAL_HOME/.config/kde_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    for file in "${PLASMA_FILES[@]}"; do
        [[ -f "$REAL_HOME/.config/$file" ]] && cp "$REAL_HOME/.config/$file" "$BACKUP_DIR"/
        cp "$REPO_DIR"/plasma/"$file" "$REAL_HOME/.config/$file"
    done

    # Set Vimix cursor theme in kdeglobals and kcminputrc
    local kwrite
    if command -v kwriteconfig6 &> /dev/null; then
        kwrite="kwriteconfig6"
    elif command -v kwriteconfig5 &> /dev/null; then
        kwrite="kwriteconfig5"
    fi

    if [[ -n "$kwrite" ]]; then
        "$kwrite" --file "$REAL_HOME/.config/kdeglobals"  --group Icons --key cursorTheme "Vimix-cursors"
        "$kwrite" --file "$REAL_HOME/.config/kcminputrc"  --group Mouse --key cursorTheme "Vimix-cursors"
        echo -e "${GREEN}Cursor theme set to Vimix-cursors.${NC}"
    else
        # Fallback: write directly to config files
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
        echo -e "${GREEN}Cursor theme set to Vimix-cursors (fallback method).${NC}"
    fi

    # Set cursor theme for X11 (GTK apps + X server)
    mkdir -p "$REAL_HOME/.icons/default"
    cat > "$REAL_HOME/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default cursor theme
Inherits=Vimix-cursors
EOF

    if grep -q "Xcursor.theme" "$REAL_HOME/.Xresources" 2>/dev/null; then
        sed -i 's/^Xcursor\.theme:.*/Xcursor.theme: Vimix-cursors/' "$REAL_HOME/.Xresources"
    else
        printf '\nXcursor.theme: Vimix-cursors\nXcursor.size: 24\n' >> "$REAL_HOME/.Xresources"
    fi

    # Export XCURSOR_THEME for all X11 session applications
    if grep -q "XCURSOR_THEME" "$REAL_HOME/.xprofile" 2>/dev/null; then
        sed -i 's/^export XCURSOR_THEME=.*/export XCURSOR_THEME=Vimix-cursors/' "$REAL_HOME/.xprofile"
    else
        printf '\nexport XCURSOR_THEME=Vimix-cursors\nexport XCURSOR_SIZE=24\n' >> "$REAL_HOME/.xprofile"
    fi

    # GTK 2
    mkdir -p "$REAL_HOME/.config"
    if grep -q "gtk-cursor-theme-name" "$REAL_HOME/.gtkrc-2.0" 2>/dev/null; then
        sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name="Vimix-cursors"/' "$REAL_HOME/.gtkrc-2.0"
    else
        printf '\ngtk-cursor-theme-name="Vimix-cursors"\ngtk-cursor-theme-size=24\n' >> "$REAL_HOME/.gtkrc-2.0"
    fi

    # GTK 3
    mkdir -p "$REAL_HOME/.config/gtk-3.0"
    if grep -q "gtk-cursor-theme-name" "$REAL_HOME/.config/gtk-3.0/settings.ini" 2>/dev/null; then
        sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Vimix-cursors/' "$REAL_HOME/.config/gtk-3.0/settings.ini"
    else
        printf '\n[Settings]\ngtk-cursor-theme-name=Vimix-cursors\ngtk-cursor-theme-size=24\n' >> "$REAL_HOME/.config/gtk-3.0/settings.ini"
    fi

    # GTK 4
    mkdir -p "$REAL_HOME/.config/gtk-4.0"
    if grep -q "gtk-cursor-theme-name" "$REAL_HOME/.config/gtk-4.0/settings.ini" 2>/dev/null; then
        sed -i 's/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Vimix-cursors/' "$REAL_HOME/.config/gtk-4.0/settings.ini"
    else
        printf '\n[Settings]\ngtk-cursor-theme-name=Vimix-cursors\ngtk-cursor-theme-size=24\n' >> "$REAL_HOME/.config/gtk-4.0/settings.ini"
    fi

    echo -e "${GREEN}X11 cursor theme configured (X11, GTK2/3/4, session env).${NC}"

    echo -e "${GREEN}KDE Plasma settings restored.${NC}"
}

apply_session_changes() {
    echo -e "${YELLOW}[8/8] Finalizing changes...${NC}"
    CURRENT_SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

    if [ "$CURRENT_SESSION_TYPE" = "wayland" ]; then
        echo -e "${YELLOW}You are currently on Wayland. Reboot to use Plasma X11.${NC}"
        echo -e "${BLUE}SDDM is already configured for Plasma X11.${NC}"
    else
        echo -e "${GREEN}You are on X11. Restarting Plasma Shell...${NC}"
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
}

# --- Execution ---

echo -e "${BLUE}Starting KDE Tuning Setup...${NC}"

# Only keep sudo alive if we're running with sudo privileges
if [ "$EUID" -ne 0 ] && command -v sudo &> /dev/null; then
    if sudo -n true 2>/dev/null; then
        # sudo credentials already available (from previous sudo invocation)
        keep_sudo_alive
    else
        # No sudo credentials yet; request them once
        echo -e "${YELLOW}Some tasks require administrator privileges (sudo).${NC}"
        sudo -v || exit 1
        keep_sudo_alive
    fi
fi

install_dependencies
configure_x11_session
install_external_repos
install_fonts
setup_conky
setup_zsh
restore_plasma_config
apply_session_changes

echo -e "${GREEN}Setup finished! Please restart your session if you didn't logout already.${NC}"
