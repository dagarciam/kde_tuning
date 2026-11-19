#!/bin/bash
# ==============================================================================
# lib/grub.sh - GRUB2 theme installation (AdisonCavani/distro-grub-themes)
# ==============================================================================

[[ -n "${_LIB_GRUB_LOADED:-}" ]] && return 0
_LIB_GRUB_LOADED=1

GRUB_THEMES_REPO="https://github.com/AdisonCavani/distro-grub-themes.git"

# Map detected DISTRO_ID / DISTRO_FAMILY to a theme name in distro-grub-themes
resolve_grub_theme_name() {
    case "$DISTRO_ID" in
        manjaro)     echo "manjaro" ;;
        arch)        echo "arch-linux" ;;
        endeavouros) echo "endeavouros" ;;
        garuda)      echo "garuda" ;;
        cachyos)     echo "arch-linux" ;;
        artix)       echo "artix-linux" ;;
        arcolinux*)  echo "arco-linux" ;;
        ubuntu)      echo "ubuntu" ;;
        kubuntu)     echo "kubuntu" ;;
        neon)        echo "kde-neon" ;;
        debian)      echo "debian" ;;
        linuxmint)   echo "linux-mint" ;;
        pop)         echo "pop-os" ;;
        fedora)      echo "fedora" ;;
        nobara)      echo "nobara" ;;
        opensuse*)   echo "opensuse" ;;
        nixos)       echo "nixos" ;;
        *)
            resolve_grub_family_fallback
            ;;
    esac
}

resolve_grub_family_fallback() {
    case "$DISTRO_FAMILY" in
        arch)   echo "arch-linux" ;;
        fedora) echo "fedora" ;;
        debian) echo "ubuntu" ;;
        suse)   echo "opensuse" ;;
        *)      echo "arch-linux" ;;
    esac
}

detect_grub_cfg_path() {
    if [[ -f /boot/grub/grub.cfg ]] || [[ -d /boot/grub ]]; then
        echo "/boot/grub/grub.cfg"
    elif [[ -f /boot/grub2/grub.cfg ]] || [[ -d /boot/grub2 ]]; then
        echo "/boot/grub2/grub.cfg"
    else
        local efi_cfg=""
        efi_cfg="$(find /boot/efi/EFI -maxdepth 2 -name grub.cfg 2>/dev/null | head -n 1 || true)"
        echo "$efi_cfg"
    fi
}

ensure_os_prober() {
    if command -v os-prober &>/dev/null; then
        log_ok "os-prober already installed"
        return 0
    fi

    log_info "Installing os-prober via ${PKG_MANAGER}..."
    case "$PKG_MANAGER" in
        pacman) run_as_root pacman -S --needed --noconfirm os-prober || log_warn "Failed to install os-prober via pacman." ;;
        dnf)    run_as_root dnf install -y os-prober || log_warn "Failed to install os-prober via dnf." ;;
        apt)    run_as_root apt-get install -y os-prober || log_warn "Failed to install os-prober via apt-get." ;;
        zypper) run_as_root zypper --non-interactive install --no-recommends os-prober || log_warn "Failed to install os-prober via zypper." ;;
        *)      log_warn "Unsupported package manager '$PKG_MANAGER': install os-prober manually." ;;
    esac
}

scan_existing_oses() {
    if ! command -v os-prober &>/dev/null; then
        log_warn "os-prober not available; skipping multi-OS scan."
        return 0
    fi

    log_info "Scanning for existing operating systems (os-prober)..."
    local detected=""
    detected="$(run_as_root os-prober 2>/dev/null || true)"
    if [[ -n "$detected" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && log_ok "Detected OS: $line"
        done <<< "$detected"
    else
        log_info "No additional OSes detected by os-prober (only current system)."
    fi
}

# If the system boots via UKI (15_uki present and 10_linux disabled), add a custom
# menuentry in /etc/grub.d/40_custom with --class <distro> so the GRUB theme displays its icon,
# and disable 15_uki to prevent duplicate entries.
configure_grub_uki_entry() {
    local custom_file="/etc/grub.d/40_custom"
    [[ -f /etc/grub.d/15_uki && ! -x /etc/grub.d/10_linux && -f "$custom_file" ]] || return 0

    local uki_path=""
    uki_path="$(grep -hE '^[[:space:]]*default_uki=' /etc/mkinitcpio.d/*.preset 2>/dev/null | head -n 1 | sed -E 's/^[^=]+=["'\'']?([^"'\'']+)["'\'']?/\1/' || true)"
    [[ -n "$uki_path" ]] || return 0

    local esp_uuid="" uki_rel=""
    for mnt in /efi /boot/efi /boot; do
        if [[ "$uki_path" == "${mnt}/"* ]]; then
            esp_uuid="$(findmnt -no UUID "$mnt" 2>/dev/null || true)"
            if [[ -n "$esp_uuid" ]]; then
                uki_rel="/${uki_path#"${mnt}/"}"
                break
            fi
        fi
    done

    if [[ -z "$esp_uuid" || -z "$uki_rel" ]]; then
        log_warn "Could not resolve ESP UUID for UKI '$uki_path'; skipping 40_custom entry."
        return 0
    fi

    local icon_class="$DISTRO_ID"
    local entry_title="Linux (UKI)"
    case "$DISTRO_ID" in
        arch)    icon_class="arch"; entry_title="Arch Linux" ;;
        manjaro) icon_class="manjaro"; entry_title="Manjaro Linux" ;;
        *)       entry_title="${DISTRO_ID^} Linux" ;;
    esac
    [[ "$uki_rel" == *"-lts"* ]] && entry_title="${entry_title} (LTS)"

    if $DRY_RUN; then
        log_dry "UKI detected ($uki_path on ESP UUID=$esp_uuid): would add '--class $icon_class' entry '$entry_title' -> '$uki_rel' to $custom_file"
        [[ -x /etc/grub.d/15_uki ]] && log_dry "Would disable /etc/grub.d/15_uki (chmod -x) to avoid duplicate UKI entries"
        return 0
    fi

    log_info "Adding UKI menuentry '$entry_title' (--class $icon_class) to ${custom_file}..."
    local tmp_custom
    tmp_custom="$(mktemp)"
    awk '
        /^# BEGIN kde_tuning UKI$/ { skip=1; next }
        /^# END kde_tuning UKI$/   { skip=0; next }
        !skip { print }
    ' "$custom_file" > "$tmp_custom"

    cat >> "$tmp_custom" <<EOF
# BEGIN kde_tuning UKI
menuentry "${entry_title}" --class ${icon_class} --class gnu-linux --class gnu --class os {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root ${esp_uuid}
    chainloader ${uki_rel}
}
# END kde_tuning UKI
EOF

    run_as_root cp "$tmp_custom" "$custom_file"
    run_as_root chmod +x "$custom_file"
    rm -f "$tmp_custom"
    log_ok "UKI entry configured in ${custom_file}"

    if [[ -x /etc/grub.d/15_uki ]]; then
        run_as_root chmod -x /etc/grub.d/15_uki
        log_ok "Disabled /etc/grub.d/15_uki to avoid duplicate UKI entries"
    fi
}

setup_grub_theme() {
    log_progress "$1" "$2" "Installing GRUB2 theme"

    if [[ ! -f /etc/default/grub ]]; then
        log_warn "/etc/default/grub not found (system may use systemd-boot or another bootloader); skipping GRUB theme."
        return 0
    fi

    local theme_name
    theme_name="$(resolve_grub_theme_name)"
    local themes_base="/usr/share/grub/themes"
    [[ -d /boot/grub2 && ! -d /usr/share/grub ]] && themes_base="/boot/grub2/themes"

    local repo_dir="$REAL_HOME/distro-grub-themes"
    local theme_dir="${themes_base}/${theme_name}"
    local grub_cfg=""
    grub_cfg="$(detect_grub_cfg_path)"

    if $DRY_RUN; then
        log_dry "Detected distro '$DISTRO_ID' (family: '$DISTRO_FAMILY') -> GRUB theme: '$theme_name'"
        log_dry "Would ensure os-prober is installed via '$PKG_MANAGER'"
        log_dry "Would clone $GRUB_THEMES_REPO (shallow) into $repo_dir if missing"
        log_dry "Would extract themes/${theme_name}.tar into $theme_dir"
        log_dry "Would backup /etc/default/grub, set GRUB_THEME=\"${theme_dir}/theme.txt\", GRUB_DISABLE_OS_PROBER=false, and GRUB_DISABLE_BOOTNEXT=true"
        log_dry "Would run os-prober to identify existing OSes on the PC"
        configure_grub_uki_entry
        if command -v update-grub &>/dev/null; then
            log_dry "Would run: update-grub"
        elif command -v grub-mkconfig &>/dev/null && [[ -n "$grub_cfg" ]]; then
            log_dry "Would run: grub-mkconfig -o $grub_cfg"
        elif command -v grub2-mkconfig &>/dev/null && [[ -n "$grub_cfg" ]]; then
            log_dry "Would run: grub2-mkconfig -o $grub_cfg"
        else
            log_dry "Would regenerate GRUB config (grub-mkconfig / update-grub)"
        fi
        log_ok "GRUB2 theme setup (dry-run)"
        return 0
    fi

    ensure_os_prober

    if ! command -v tar &>/dev/null; then
        log_warn "'tar' is required to extract GRUB themes; skipping."
        return 0
    fi

    if [[ ! -d "$repo_dir" ]]; then
        log_info "Cloning distro-grub-themes..."
        git clone --depth 1 "$GRUB_THEMES_REPO" "$repo_dir"
    else
        log_ok "distro-grub-themes repository already present"
    fi

    local tar_file="${repo_dir}/themes/${theme_name}.tar"
    if [[ ! -f "$tar_file" ]]; then
        local fallback_name
        fallback_name="$(resolve_grub_family_fallback)"
        if [[ -f "${repo_dir}/themes/${fallback_name}.tar" ]]; then
            log_warn "Theme '${theme_name}.tar' not found; falling back to '${fallback_name}'."
            theme_name="$fallback_name"
            theme_dir="${themes_base}/${theme_name}"
            tar_file="${repo_dir}/themes/${theme_name}.tar"
        else
            log_warn "No matching GRUB theme archive found for '$DISTRO_ID' in ${repo_dir}/themes; skipping."
            return 0
        fi
    fi

    log_info "Extracting GRUB theme '${theme_name}' to ${theme_dir}..."
    run_as_root mkdir -p "$theme_dir"
    run_as_root tar -xf "$tar_file" -C "$theme_dir"

    if [[ ! -f "${theme_dir}/theme.txt" ]]; then
        log_warn "theme.txt not found after extracting ${tar_file}; skipping /etc/default/grub update."
        return 0
    fi

    local grub_default="/etc/default/grub"
    local grub_backup="${grub_default}.bak.${LOG_TIMESTAMP}"
    log_info "Backing up ${grub_default} to ${grub_backup}..."
    run_as_root cp "$grub_default" "$grub_backup"

    # Ensure graphical terminal is not forced to text console
    if grep -qE '^[[:space:]]*GRUB_TERMINAL_OUTPUT="?console"?' "$grub_default"; then
        run_as_root sed -i -E 's|^([[:space:]]*GRUB_TERMINAL_OUTPUT="?console"?)|# \1|' "$grub_default"
    fi

    # Set or update GRUB_THEME idempotently
    if grep -qE '^[[:space:]]*#?[[:space:]]*GRUB_THEME=' "$grub_default"; then
        run_as_root sed -i -E "s|^[[:space:]]*#?[[:space:]]*GRUB_THEME=.*|GRUB_THEME=\"${theme_dir}/theme.txt\"|" "$grub_default"
    else
        printf '\nGRUB_THEME="%s/theme.txt"\n' "$theme_dir" | run_as_root tee -a "$grub_default" >/dev/null
    fi

    # Ensure GRUB_GFXMODE is set if only commented out
    if grep -qE '^[[:space:]]*#[[:space:]]*GRUB_GFXMODE=' "$grub_default" && ! grep -qE '^[[:space:]]*GRUB_GFXMODE=' "$grub_default"; then
        run_as_root sed -i -E 's|^[[:space:]]*#[[:space:]]*GRUB_GFXMODE=.*|GRUB_GFXMODE=auto|' "$grub_default"
    fi

    # Enable os-prober so GRUB detects other installed operating systems
    if grep -qE '^[[:space:]]*#?[[:space:]]*GRUB_DISABLE_OS_PROBER=' "$grub_default"; then
        run_as_root sed -i -E 's|^[[:space:]]*#?[[:space:]]*GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' "$grub_default"
    else
        printf 'GRUB_DISABLE_OS_PROBER=false\n' | run_as_root tee -a "$grub_default" >/dev/null
    fi

    # Disable 31_efi_bootnext entries to avoid cluttering GRUB with NVRAM devices/old entries
    if grep -qE '^[[:space:]]*#?[[:space:]]*GRUB_DISABLE_BOOTNEXT=' "$grub_default"; then
        run_as_root sed -i -E 's|^[[:space:]]*#?[[:space:]]*GRUB_DISABLE_BOOTNEXT=.*|GRUB_DISABLE_BOOTNEXT=true|' "$grub_default"
    else
        printf 'GRUB_DISABLE_BOOTNEXT=true\n' | run_as_root tee -a "$grub_default" >/dev/null
    fi

    scan_existing_oses
    configure_grub_uki_entry

    # Regenerate GRUB configuration
    if command -v update-grub &>/dev/null; then
        log_info "Updating GRUB configuration (update-grub)..."
        run_as_root update-grub
    elif command -v grub-mkconfig &>/dev/null && [[ -n "$grub_cfg" ]]; then
        log_info "Updating GRUB configuration (grub-mkconfig -o ${grub_cfg})..."
        run_as_root grub-mkconfig -o "$grub_cfg"
    elif command -v grub2-mkconfig &>/dev/null && [[ -n "$grub_cfg" ]]; then
        log_info "Updating GRUB configuration (grub2-mkconfig -o ${grub_cfg})..."
        run_as_root grub2-mkconfig -o "$grub_cfg"
    else
        log_warn "Could not find update-grub / grub-mkconfig / grub2-mkconfig or grub.cfg path; please regenerate grub.cfg manually."
        return 0
    fi

    log_ok "GRUB2 theme '${theme_name}' installed and configured"
}
