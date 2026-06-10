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

# --- 0. External Dependencies ---
echo -e "${YELLOW}[0/5] Checking external dependencies...${NC}"

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

# Tools (zoxide and fzf)
if ! command -v zoxide &> /dev/null; then
    echo "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi
if ! command -v fzf &> /dev/null; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
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

# --- 1. Fonts Installation ---
echo -e "${YELLOW}[1/5] Installing fonts...${NC}"
mkdir -p ~/.local/share/fonts
cp "$REPO_DIR"/conky/Mimosa/fonts/*.ttf ~/.local/share/fonts/
python3 -m zipfile -e "$REPO_DIR"/conky/Mimosa/fonts/Abel.zip ~/.local/share/fonts/
fc-cache -fv > /dev/null
echo -e "${GREEN}Fonts installed successfully.${NC}"

# --- 2. Conky Setup ---
echo -e "${YELLOW}[2/5] Setting up Conky Mimosa...${NC}"
mkdir -p ~/.config/conky
cp -r "$REPO_DIR"/conky/Mimosa ~/.config/conky/
chmod +x ~/.config/conky/Mimosa/start.sh
chmod +x ~/.config/conky/Mimosa/scripts/*

# Setup Autostart
mkdir -p ~/.config/autostart
cp "$REPO_DIR"/conky/conky-mimosa.desktop ~/.config/autostart/
echo -e "${GREEN}Conky setup complete.${NC}"

# --- 3. Zsh Configuration ---
echo -e "${YELLOW}[3/5] Applying Zsh & Powerlevel10k config...${NC}"
[ -f ~/.zshrc ] && cp ~/.zshrc ~/.zshrc.bak
[ -f ~/.p10k.zsh ] && cp ~/.p10k.zsh ~/.p10k.zsh.bak

cp "$REPO_DIR"/zsh/.zshrc ~/.zshrc
cp "$REPO_DIR"/zsh/.p10k.zsh ~/.p10k.zsh
echo -e "${GREEN}Zsh configuration applied (backups created).${NC}"

# --- 4. KDE Plasma Settings ---
echo -e "${YELLOW}[4/5] Restoring KDE Plasma configuration...${NC}"
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
echo -e "${YELLOW}Please RESTART your terminal to see Zsh changes.${NC}"
echo -e "${BLUE}====================================================${NC}"
