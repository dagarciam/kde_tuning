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
NC='\033[0m' # No Color

echo -e "${BLUE}Starting KDE Tuning Setup...${NC}"

# Get the script directory
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- 1. Fonts Installation ---
echo -e "${YELLOW}[1/4] Installing fonts...${NC}"
mkdir -p ~/.local/share/fonts
cp "$REPO_DIR"/conky/Mimosa/fonts/*.ttf ~/.local/share/fonts/
python3 -m zipfile -e "$REPO_DIR"/conky/Mimosa/fonts/Abel.zip ~/.local/share/fonts/
fc-cache -fv > /dev/null
echo -e "${GREEN}Fonts installed successfully.${NC}"

# --- 2. Conky Setup ---
echo -e "${YELLOW}[2/4] Setting up Conky Mimosa...${NC}"
mkdir -p ~/.config/conky
cp -r "$REPO_DIR"/conky/Mimosa ~/.config/conky/
chmod +x ~/.config/conky/Mimosa/start.sh
chmod +x ~/.config/conky/Mimosa/scripts/*

# Setup Autostart
mkdir -p ~/.config/autostart
cp "$REPO_DIR"/conky/conky-mimosa.desktop ~/.config/autostart/
echo -e "${GREEN}Conky setup complete.${NC}"

# --- 3. Zsh Configuration ---
echo -e "${YELLOW}[3/4] Applying Zsh & Powerlevel10k config...${NC}"
[ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.bak
[ -f ~/.p10k.zsh ] && cp ~/.p10k.zsh ~/.p10k.zsh.bak

cp "$REPO_DIR"/zsh/.zshrc ~/.zshrc
cp "$REPO_DIR"/zsh/.p10k.zsh ~/.p10k.zsh
echo -e "${GREEN}Zsh configuration applied (backups created).${NC}"

# --- 4. KDE Plasma Settings ---
echo -e "${YELLOW}[4/4] Restoring KDE Plasma configuration...${NC}"
echo "Note: Some changes might require a logout/login to take full effect."

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

echo -e "${GREEN}KDE Plasma settings restored (backups created in ~/.config/kde_backup_...).${NC}"

echo -e "${BLUE}====================================================${NC}"
echo -e "${GREEN}Setup finished! Enjoy your tuned KDE environment.${NC}"
echo -e "${YELLOW}Recommended: Restart Plasmashell or Logout/Login.${NC}"
echo -e "${BLUE}====================================================${NC}"
