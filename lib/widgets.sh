#!/bin/bash
# ==============================================================================
# lib/widgets.sh - Desktop widgets setup (Mimosa AGS and Conky)
# ==============================================================================

[[ -n "${_LIB_WIDGETS_LOADED:-}" ]] && return 0
_LIB_WIDGETS_LOADED=1

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
