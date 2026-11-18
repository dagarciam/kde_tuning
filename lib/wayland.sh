#!/bin/bash
# ==============================================================================
# lib/wayland.sh - Plasma Wayland session, SDDM, and touchpad configuration
# ==============================================================================

[[ -n "${_LIB_WAYLAND_LOADED:-}" ]] && return 0
_LIB_WAYLAND_LOADED=1

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
    if [[ ! -f "$sddm_session_file" && -f "/usr/share/wayland-sessions/plasmawayland.desktop" ]]; then
        sddm_session="plasmawayland"
        sddm_session_file="/usr/share/wayland-sessions/plasmawayland.desktop"
    fi
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

    local sddm_theme="breath"
    if [[ ! -d "/usr/share/sddm/themes/breath" ]]; then
        if [[ -d "/usr/share/sddm/themes/breeze" ]]; then
            sddm_theme="breeze"
        else
            sddm_theme=""
        fi
    fi

    if $DRY_RUN; then
        log_dry "mkdir -p $conf_dir"
        log_dry "cp $template_conf $sddm_conf"
        log_dry "sed -i 's/User=.*/User=$REAL_USER/' $sddm_conf"
        log_dry "set Session=$sddm_session in $sddm_conf"
        [[ -n "$sddm_theme" ]] && log_dry "set Current=$sddm_theme in $sddm_conf"
        log_dry "write /var/lib/sddm/state.conf (Wayland)"
        log_dry "write /var/lib/sddm/.config/state.conf (Wayland)"
        log_dry "chown -R sddm:sddm /var/lib/sddm"
    else
        log_info "Copying SDDM Wayland template to $sddm_conf..."
        run_as_root mkdir -p "$conf_dir"
        run_as_root cp "$template_conf" "$sddm_conf"
        run_as_root sed -i -E "s|^User=.*$|User=$REAL_USER|" "$sddm_conf"
        run_as_root sed -i -E "s|^Session=.*$|Session=$sddm_session|" "$sddm_conf"
        if [[ -n "$sddm_theme" ]]; then
            run_as_root sed -i -E "s|^Current=.*$|Current=$sddm_theme|" "$sddm_conf"
        fi

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
