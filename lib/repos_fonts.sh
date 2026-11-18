#!/bin/bash
# ==============================================================================
# lib/repos_fonts.sh - External git themes, plugins, and custom fonts
# ==============================================================================

[[ -n "${_LIB_REPOS_FONTS_LOADED:-}" ]] && return 0
_LIB_REPOS_FONTS_LOADED=1

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
        if [[ "$DISTRO_FAMILY" != "arch" ]]; then
            log_dry "Ensure Hack Nerd Font is installed (download from GitHub releases if missing)"
        fi
        log_dry "fc-cache -fv"
    else
        if ! compgen -G "$REPO_DIR/ags/fonts/*.ttf" > /dev/null; then
            error_exit "No .ttf files found in $REPO_DIR/ags/fonts"
        fi

        cp "$REPO_DIR"/ags/fonts/*.ttf "$REAL_HOME/.local/share/fonts/"

        # On non-Arch distros, ttf-hack-nerd is not in standard repos; fetch from Nerd Fonts if missing
        if [[ "$DISTRO_FAMILY" != "arch" ]]; then
            if ! fc-list : family 2>/dev/null | grep -qi "Hack Nerd Font"; then
                if command -v curl &>/dev/null && command -v unzip &>/dev/null; then
                    log_info "Downloading Hack Nerd Font..."
                    local tmp_zip
                    tmp_zip="$(mktemp --suffix=.zip)"
                    if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip" -o "$tmp_zip"; then
                        mkdir -p "$REAL_HOME/.local/share/fonts/HackNerdFont"
                        unzip -qo "$tmp_zip" "*.ttf" -d "$REAL_HOME/.local/share/fonts/HackNerdFont" || log_warn "Failed to extract Hack Nerd Font"
                    else
                        log_warn "Failed to download Hack Nerd Font; Nerd Font icons may not render."
                    fi
                    rm -f "$tmp_zip"
                else
                    log_warn "curl/unzip unavailable; skipping Hack Nerd Font download."
                fi
            fi
        fi

        fc-cache -fv > /dev/null
    fi

    log_ok "Fonts installed"
}
