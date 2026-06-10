#!/bin/bash

# ==============================================================================
# KDE Tuning - Master Setup Script
# Author: dagarciam
# Description: Automates the deployment of Conky, Zsh, and KDE configurations.
# ==============================================================================

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting KDE Tuning Setup...${NC}"

# Get the script directory
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- 0. Install System Dependencies ---
echo -e "${YELLOW}[0/7] Installing system dependencies...${NC}"

# Define dependencies
PKGS=(
    "conky"
    "playerctl"
    "jq"
    "curl"
    "git"
    "zsh",
    "python",
    "fzf",
    "zoxide",
    "fastfetch",
    "lazygit",
    "git-delta",
    "plasma-workspace-x11",
    "lm_sensors"
    "wireless_tools"
)

# Detect package manager (favor yay if available)
if command -v yay &> /dev/null; then
    INSTALL_CMD="yay -S --needed --noconfirm"
else
    INSTALL_CMD="sudo pacman -S --needed --noconfirm"
fi

echo -e "Using command: ${BLUE}$INSTALL_CMD${NC}"
$INSTALL_CMD "${PKGS[@]}"

# --- 1. System Checks (X11 Support) ---
echo -e "${YELLOW}[1/7] Checking system compatibility...${NC}"

# Check for X11 session support (Crucial for Plasma 6+)
if ! pacman -Qs plasma-workspace-x11 &> /dev/null; then
    echo -e "${RED}Warning: plasma-workspace-x11 not detected.${NC}"
    echo "This is required for Conky's Lua/Xlib rings to work in modern Plasma."
else
    echo -e "${GREEN}X11 support detected.${NC}"
fi

# Force Plasma X11 as default session to avoid Conky issues on Wayland
echo -e "${YELLOW}Configuring Plasma X11 as default session...${NC}"
X11_SESSION_FILE=""
for session_file in plasma.desktop plasmax11.desktop plasma-x11.desktop; do
    if [ -f "/usr/share/xsessions/$session_file" ]; then
        X11_SESSION_FILE="$session_file"
        break
    fi
done

if [ -z "$X11_SESSION_FILE" ]; then
    echo -e "${RED}Warning: Could not find a Plasma X11 session file in /usr/share/xsessions.${NC}"
else
    cat > ~/.dmrc <<EOF
[Desktop]
Session=$X11_SESSION_FILE
EOF
    chmod 644 ~/.dmrc
    echo -e "${GREEN}User session default set to ${X11_SESSION_FILE}.${NC}"

    if command -v sudo &> /dev/null; then
        if sudo mkdir -p /var/lib/sddm/.config && sudo tee /var/lib/sddm/.config/state.conf > /dev/null <<EOF
[Last]
Session=$X11_SESSION_FILE
User=$USER
EOF
        then
            echo -e "${GREEN}SDDM default session updated to ${X11_SESSION_FILE}.${NC}"
        else
            echo -e "${YELLOW}Could not update SDDM state file automatically.${NC}"
            echo "You can set it manually in /var/lib/sddm/.config/state.conf"
        fi
    fi
fi

# --- 2. External Repositories ---
echo -e "${YELLOW}[2/7] Checking external repositories...${NC}"

# Powerlevel10k
if [ ! -d ~/powerlevel10k ]; then
    echo "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ~/powerlevel10k
fi

# Zsh Plugins
mkdir -p ~/.zsh-plugins
if [ ! -d ~/.zsh-plugins/zsh-autosuggestions ]; then
    echo "Installing zsh-autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh-plugins/zsh-autosuggestions
fi
if [ ! -d ~/.zsh-plugins/zsh-syntax-highlighting ]; then
    echo "Installing zsh-syntax-highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.zsh-plugins/zsh-syntax-highlighting
fi

# KDE Themes
if [ ! -d ~/Orchis-kde ]; then
    echo "Installing Orchis KDE Theme..."
    git clone https://github.com/vinceliuice/Orchis-kde.git ~/Orchis-kde
    ~/Orchis-kde/install.sh
fi
if [ ! -d ~/tela-circle-icon-theme ]; then
    echo "Installing Tela Circle Icons..."
    git clone https://github.com/vinceliuice/tela-circle-icon-theme.git ~/tela-circle-icon-theme
    ~/tela-circle-icon-theme/install.sh -a
fi

# --- 3. Fonts Installation ---
echo -e "${YELLOW}[3/7] Installing fonts...${NC}"
mkdir -p ~/.local/share/fonts
cp "$REPO_DIR"/conky/Mimosa/fonts/*.ttf ~/.local/share/fonts/
python3 -m zipfile -e "$REPO_DIR"/conky/Mimosa/fonts/Abel.zip ~/.local/share/fonts/
fc-cache -fv > /dev/null
echo -e "${GREEN}Fonts installed successfully.${NC}"

# --- 4. Conky Setup ---
echo -e "${YELLOW}[4/7] Setting up Conky Mimosa...${NC}"
mkdir -p ~/.config/conky
cp -r "$REPO_DIR"/conky/Mimosa ~/.config/conky/
chmod +x ~/.config/conky/Mimosa/start.sh
chmod +x ~/.config/conky/Mimosa/scripts/*

# Setup Autostart
mkdir -p ~/.config/autostart
cp "$REPO_DIR"/conky/conky-mimosa.desktop ~/.config/autostart/
echo -e "${GREEN}Conky setup complete.${NC}"

# --- 5. Zsh Configuration ---
echo -e "${YELLOW}[5/7] Applying Zsh & Powerlevel10k config...${NC}"
[ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.bak
[ -f ~/.p10k.zsh ] && cp ~/.p10k.zsh ~/.p10k.zsh.bak

cp "$REPO_DIR"/zsh/.zshrc ~/.zshrc
cp "$REPO_DIR"/zsh/.p10k.zsh ~/.p10k.zsh
echo -e "${GREEN}Zsh configuration applied.${NC}"

# --- 6. KDE Plasma Settings ---
echo -e "${YELLOW}[6/7] Restoring KDE Plasma configuration...${NC}"
PLASMA_FILES=(
    "plasma-org.kde.plasma.desktop-appletsrc"
    "plasmashellrc"
    "kglobalshortcutsrc"
    "kwinrc"
    "kdeglobals"
    "kactivitymanagerdrc"
)

mkdir -p ~/.config/kde_backup_$(date +%Y%m%d_%H%M%S)

for file in "${PLASMA_FILES[@]}"; do
    if [ -f ~/.config/"$file" ]; then
        cp ~/.config/"$file" ~/.config/kde_backup_$(date +%Y%m%d_%H%M%S)/
    fi
    cp "$REPO_DIR"/plasma/"$file" ~/.config/"$file"
done
echo -e "${GREEN}KDE Plasma settings restored.${NC}"

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Setup finished! Enjoy your tuned environment.${NC}"
echo -e "${YELLOW}Please RESTART your session or Logout/Login.${NC}"
echo -e "${BLUE}====================================================${NC}"
