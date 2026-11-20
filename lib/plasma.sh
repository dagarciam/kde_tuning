#!/bin/bash
# ==============================================================================
# lib/plasma.sh - KDE Plasma theme, cursor, shortcuts, and layout restoration
# ==============================================================================

[[ -n "${_LIB_PLASMA_LOADED:-}" ]] && return 0
_LIB_PLASMA_LOADED=1

detect_plasma_major() {
    local ver=""
    if command -v plasmashell &>/dev/null; then
        ver="$(plasmashell --version 2>/dev/null | awk '{print $2}' | cut -d. -f1)"
    fi
    if [[ -z "$ver" ]]; then
        if command -v kwriteconfig6 &>/dev/null; then ver="6"
        elif command -v kwriteconfig5 &>/dev/null; then ver="5"
        else ver="6"
        fi
    fi
    echo "$ver"
}

restore_plasma_config() {
    log_progress "$1" "$2" "Restoring KDE Plasma configuration"
    local plasma_major
    plasma_major="$(detect_plasma_major)"

    local plasma_files=(
        "plasmarc" "plasma-org.kde.plasma.desktop-appletsrc" "plasmashellrc"
        "kglobalshortcutsrc" "kwinrc" "kdeglobals" "kactivitymanagerdrc"
    )

    local backup_dir="$REAL_HOME/.config/kde_backup_$(date +%Y%m%d_%H%M%S_%N)"

    if $DRY_RUN; then
        log_dry "Would create backup dir: $backup_dir"
        if [[ "$plasma_major" == "5" ]]; then
            log_dry "Plasma 5 detected: would skip Plasma 6 layout files (applets/kwin/shortcuts) and only apply theme + cursor settings"
        else
            for file in "${plasma_files[@]}"; do
                log_dry "Would backup + restore: $file"
            done
            if [[ ! -f "/usr/share/applications/org.manjaro.pamac.manager.desktop" ]]; then
                log_dry "Would replace/remove Manjaro pamac launcher in plasma-org.kde.plasma.desktop-appletsrc"
            fi
        fi
        log_dry "Would set Plasma desktop theme to dark (breeze-dark or breath-dark)"
        log_dry "Would set Vimix cursor theme in kdeglobals, kcminputrc, Xresources, xprofile, gtkrc, gtk-3.0, gtk-4.0"
        log_dry "Would configure Konsole as default terminal and Ctrl+Alt+T shortcut in kglobalshortcutsrc and kdeglobals"
        log_ok "KDE Plasma settings (dry-run)"
        return 0
    fi

    mkdir -p "$backup_dir"

    if [[ "$plasma_major" == "5" ]]; then
        log_warn "Plasma 5 detected (e.g. Kubuntu 24.04 LTS): skipping Plasma 6 layout files to avoid breaking panels/widgets; applying dark theme and cursor settings only."
        for file in "plasmarc" "kdeglobals" "kcminputrc"; do
            [[ -f "$REAL_HOME/.config/$file" ]] && cp "$REAL_HOME/.config/$file" "$backup_dir"/
        done
    else
        for file in "${plasma_files[@]}"; do
            ensure_file "$REPO_DIR/plasma/$file"
            [[ -f "$REAL_HOME/.config/$file" ]] && cp "$REAL_HOME/.config/$file" "$backup_dir"/
            cp "$REPO_DIR"/plasma/"$file" "$REAL_HOME/.config/$file"
        done

        # Replace or remove Manjaro-specific pamac launcher on non-Manjaro systems
        local applets_rc="$REAL_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
        if [[ -f "$applets_rc" && ! -f "/usr/share/applications/org.manjaro.pamac.manager.desktop" ]]; then
            if [[ -f "/usr/share/applications/org.kde.discover.desktop" ]]; then
                sed -i 's/org\.manjaro\.pamac\.manager\.desktop/org.kde.discover.desktop/g' "$applets_rc"
            elif [[ -f "/usr/share/applications/octopi.desktop" ]]; then
                sed -i 's/org\.manjaro\.pamac\.manager\.desktop/octopi.desktop/g' "$applets_rc"
            else
                sed -i -E -e 's/(applications:)?org\.manjaro\.pamac\.manager\.desktop//g' \
                          -e 's/,,+/,/g' -e 's/=,/=/g' -e 's/,$//' "$applets_rc"
            fi
        fi
    fi

    # Record which backup was created so rollback can find the latest
    echo "$backup_dir" > "$REAL_HOME/.config/.kde_last_backup"

    # Ensure a fully compatible native Plasma 6 dark SVG theme for panels, tooltips and widgets
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

    # Ensure Konsole is configured as default terminal and global shortcut Ctrl+Alt+T is active
    if [[ -n "$kwrite" ]]; then
        "$kwrite" --file "$REAL_HOME/.config/kdeglobals" --group General --key TerminalApplication "konsole"
        "$kwrite" --file "$REAL_HOME/.config/kdeglobals" --group General --key TerminalService "org.kde.konsole.desktop"
        "$kwrite" --file "$REAL_HOME/.config/kglobalshortcutsrc" --group "org.kde.konsole.desktop" --key "_k_friendly_name" "Konsole"
        "$kwrite" --file "$REAL_HOME/.config/kglobalshortcutsrc" --group "org.kde.konsole.desktop" --key "_launch" "Ctrl+Alt+T,none,Konsole"
        log_ok "Konsole configured as default terminal (Ctrl+Alt+T shortcut set)"
    else
        set_ini_key "$REAL_HOME/.config/kdeglobals" "General" "TerminalApplication" "konsole"
        set_ini_key "$REAL_HOME/.config/kdeglobals" "General" "TerminalService" "org.kde.konsole.desktop"
        set_ini_key "$REAL_HOME/.config/kglobalshortcutsrc" "org.kde.konsole.desktop" "_k_friendly_name" "Konsole"
        set_ini_key "$REAL_HOME/.config/kglobalshortcutsrc" "org.kde.konsole.desktop" "_launch" "Ctrl+Alt+T,none,Konsole"
        log_ok "Konsole configured as default terminal (fallback method)"
    fi

    # Notify KGlobalAccel to reload shortcuts if available
    local qdbus_cmd=""
    if command -v qdbus6 &>/dev/null; then
        qdbus_cmd="qdbus6"
    elif command -v qdbus &>/dev/null; then
        qdbus_cmd="qdbus"
    fi
    if [[ -n "$qdbus_cmd" ]]; then
        "$qdbus_cmd" org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel.reloadConfig &>/dev/null || true
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
