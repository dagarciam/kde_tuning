#!/bin/bash
# ==============================================================================
# lib/distro.sh - Distribution detection and package management
# ==============================================================================

[[ -n "${_LIB_DISTRO_LOADED:-}" ]] && return 0
_LIB_DISTRO_LOADED=1

DISTRO_ID="unknown"
DISTRO_FAMILY="unknown"
PKG_MANAGER="unknown"

detect_distro() {
    if [[ -r /etc/os-release ]]; then
        local os_id="" os_like=""
        os_id="$(awk -F= '$1=="ID"{gsub(/"/,"",$2); print tolower($2); exit}' /etc/os-release 2>/dev/null || true)"
        os_like="$(awk -F= '$1=="ID_LIKE"{gsub(/"/,"",$2); print tolower($2); exit}' /etc/os-release 2>/dev/null || true)"
        DISTRO_ID="${os_id:-unknown}"
        local combined=" ${os_id} ${os_like} "
        if [[ "$combined" == *" arch "* || "$combined" == *" manjaro "* || "$combined" == *" endeavouros "* || "$combined" == *" cachyos "* || "$combined" == *" garuda "* ]]; then
            DISTRO_FAMILY="arch"
            PKG_MANAGER="pacman"
        elif [[ "$combined" == *" fedora "* || "$combined" == *" rhel "* || "$combined" == *" centos "* ]]; then
            DISTRO_FAMILY="fedora"
            PKG_MANAGER="dnf"
        elif [[ "$combined" == *" debian "* || "$combined" == *" ubuntu "* || "$combined" == *" neon "* ]]; then
            DISTRO_FAMILY="debian"
            PKG_MANAGER="apt"
        elif [[ "$combined" == *" opensuse "* || "$combined" == *" suse "* ]]; then
            DISTRO_FAMILY="suse"
            PKG_MANAGER="zypper"
        fi
    fi

    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        if command -v pacman &>/dev/null; then DISTRO_FAMILY="arch"; PKG_MANAGER="pacman"
        elif command -v dnf &>/dev/null; then DISTRO_FAMILY="fedora"; PKG_MANAGER="dnf"
        elif command -v apt-get &>/dev/null; then DISTRO_FAMILY="debian"; PKG_MANAGER="apt"
        elif command -v zypper &>/dev/null; then DISTRO_FAMILY="suse"; PKG_MANAGER="zypper"
        fi
    fi
}

install_deps_arch() {
    local want_ags="$1"
    local want_conky="$2"
    ensure_cmd pacman

    local PKGS=(
        "konsole" "playerctl" "jq" "curl" "git" "zsh" "python" "fzf" "zoxide"
        "fastfetch" "lazygit" "git-delta" "lm_sensors"
        "wireless_tools" "ttf-hack-nerd" "imagemagick"
        "appmenu-gtk-module" "pacman-contrib"
    )
    $want_ags && PKGS+=("gjs" "gtk4-layer-shell")
    $want_conky && PKGS+=("conky")

    local AUR_PKGS=()
    $want_ags && AUR_PKGS+=("aylurs-gtk-shell")

    local aur_helper=""
    if command -v yay &> /dev/null; then
        aur_helper="yay"
    elif command -v paru &> /dev/null; then
        aur_helper="paru"
    fi

    local INSTALL_CMD=()
    if (( ${#AUR_PKGS[@]} > 0 )) && [[ -n "$aur_helper" ]]; then
        if [ "$EUID" -eq 0 ]; then
            INSTALL_CMD=(sudo -u "$REAL_USER" "$aur_helper" -S --needed --noconfirm)
        else
            INSTALL_CMD=("$aur_helper" -S --needed --noconfirm)
        fi
        PKGS+=("${AUR_PKGS[@]}")
    else
        INSTALL_CMD=(run_as_root pacman -S --needed --noconfirm)
        if (( ${#AUR_PKGS[@]} > 0 )); then
            log_warn "No AUR helper (yay/paru) found: skipping AUR packages (${AUR_PKGS[*]}). Install them manually to use the AGS widget."
        fi
    fi

    if $DRY_RUN; then
        log_dry "Would install packages (pacman): ${PKGS[*]}"
    else
        log_info "Using command: ${INSTALL_CMD[*]}"
        "${INSTALL_CMD[@]}" "${PKGS[@]}"
    fi
}

install_deps_fedora() {
    local want_ags="$1"
    local want_conky="$2"
    ensure_cmd dnf

    local PKGS=(
        "konsole" "playerctl" "jq" "curl" "git" "zsh" "python3" "fzf" "zoxide"
        "fastfetch" "git-delta" "lm_sensors" "wireless-tools"
        "ImageMagick" "appmenu-gtk-module" "unzip"
    )
    if dnf list --available lazygit &>/dev/null 2>&1; then
        PKGS+=("lazygit")
    else
        log_warn "lazygit not found in enabled dnf repos (enable COPR atim/lazygit or install manually)."
    fi
    $want_ags && PKGS+=("gjs" "gtk4-layer-shell")
    $want_conky && PKGS+=("conky")

    if $DRY_RUN; then
        log_dry "Would install packages (dnf): ${PKGS[*]}"
    else
        log_info "Using command: dnf install -y"
        run_as_root dnf install -y "${PKGS[@]}"
    fi
}

install_debian_github_tool() {
    local tool="$1"
    command -v "$tool" &>/dev/null && return 0

    local arch_deb="amd64"
    local arch_tar="x86_64"
    case "$(uname -m)" in
        aarch64|arm64) arch_deb="arm64"; arch_tar="arm64" ;;
    esac

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    case "$tool" in
        fastfetch)
            local url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch_deb}.deb"
            if curl -fsSL "$url" -o "$tmp_dir/fastfetch.deb"; then
                run_as_root dpkg -i "$tmp_dir/fastfetch.deb" || run_as_root apt-get install -f -y
            else
                log_warn "Failed to download fastfetch .deb from GitHub."
            fi
            ;;
        git-delta)
            local tag
            tag="$(curl -fsSL "https://api.github.com/repos/dandavison/delta/releases/latest" | jq -r '.tag_name // empty' 2>/dev/null || true)"
            if [[ -n "$tag" ]]; then
                local url="https://github.com/dandavison/delta/releases/download/${tag}/git-delta_${tag}_${arch_deb}.deb"
                if curl -fsSL "$url" -o "$tmp_dir/delta.deb"; then
                    run_as_root dpkg -i "$tmp_dir/delta.deb" || run_as_root apt-get install -f -y
                else
                    log_warn "Failed to download git-delta .deb from GitHub."
                fi
            fi
            ;;
        lazygit)
            local tag
            tag="$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name // empty' 2>/dev/null || true)"
            local ver="${tag#v}"
            if [[ -n "$ver" ]]; then
                local url="https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${ver}_Linux_${arch_tar}.tar.gz"
                if curl -fsSL "$url" -o "$tmp_dir/lazygit.tar.gz" && tar -xzf "$tmp_dir/lazygit.tar.gz" -C "$tmp_dir" lazygit; then
                    run_as_root install -m 755 "$tmp_dir/lazygit" /usr/local/bin/lazygit
                else
                    log_warn "Failed to download lazygit from GitHub."
                fi
            fi
            ;;
        zoxide)
            if curl -fsSL "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh" | BIN_DIR="$REAL_HOME/.local/bin" sh; then
                log_ok "Installed zoxide to $REAL_HOME/.local/bin"
            else
                log_warn "Failed to install zoxide."
            fi
            ;;
    esac
    rm -rf "$tmp_dir"
}

install_deps_debian() {
    local want_ags="$1"
    local want_conky="$2"
    ensure_cmd apt-get

    local PKGS=(
        "konsole" "playerctl" "jq" "curl" "git" "zsh" "python3" "fzf"
        "lm-sensors" "wireless-tools" "imagemagick"
        "appmenu-gtk3-module" "unzip"
    )
    local optional_pkgs=("zoxide" "fastfetch" "git-delta" "lazygit")
    $want_ags && PKGS+=("gjs") && optional_pkgs+=("libgtk4-layer-shell0")
    $want_conky && PKGS+=("conky-all")

    if step_is_selected "wayland" && ! compgen -G "/usr/share/wayland-sessions/plasma*.desktop" > /dev/null; then
        optional_pkgs+=("plasma-workspace-wayland")
    fi

    if $DRY_RUN; then
        if [[ "$DISTRO_ID" == "ubuntu" ]] && command -v add-apt-repository &>/dev/null; then
            log_dry "Would ensure Ubuntu 'universe' repository is enabled"
        fi
        log_dry "Would run: apt-get update"
        log_dry "Would install packages (apt-get): ${PKGS[*]} (+ available from: ${optional_pkgs[*]})"
        log_dry "Would install missing CLI tools (fastfetch/git-delta/lazygit/zoxide) via GitHub releases if absent from apt"
    else
        if [[ "$DISTRO_ID" == "ubuntu" ]] && command -v add-apt-repository &>/dev/null; then
            run_as_root add-apt-repository -y universe 2>/dev/null || true
        fi
        run_as_root apt-get update

        local missing_cli=()
        for opt_pkg in "${optional_pkgs[@]}"; do
            if apt-cache show "$opt_pkg" &>/dev/null; then
                PKGS+=("$opt_pkg")
            elif [[ "$opt_pkg" == "fastfetch" || "$opt_pkg" == "git-delta" || "$opt_pkg" == "lazygit" || "$opt_pkg" == "zoxide" ]]; then
                missing_cli+=("$opt_pkg")
            else
                log_warn "Package '$opt_pkg' not available in apt repos; skipping."
            fi
        done

        log_info "Using command: apt-get install -y"
        run_as_root apt-get install -y "${PKGS[@]}"

        for tool in "${missing_cli[@]}"; do
            log_info "Installing '$tool' from GitHub releases (not in apt)..."
            install_debian_github_tool "$tool"
        done
    fi
}

install_deps_suse() {
    local want_ags="$1"
    local want_conky="$2"
    ensure_cmd zypper

    local PKGS=(
        "konsole" "playerctl" "jq" "curl" "git" "zsh" "python3" "fzf" "zoxide"
        "fastfetch" "lazygit" "git-delta" "sensors" "wireless-tools"
        "ImageMagick" "appmenu-gtk-module" "unzip"
    )
    $want_ags && PKGS+=("gjs" "gtk4-layer-shell")
    $want_conky && PKGS+=("conky")

    if $DRY_RUN; then
        log_dry "Would install packages (zypper): ${PKGS[*]}"
    else
        log_info "Using command: zypper --non-interactive install --no-recommends"
        run_as_root zypper --non-interactive install --no-recommends "${PKGS[@]}"
    fi
}

install_dependencies() {
    log_progress "$1" "$2" "Installing system dependencies ($PKG_MANAGER)"

    local want_ags=false
    local want_conky=false
    if step_is_selected "ags"; then want_ags=true; fi
    if step_is_selected "conky"; then want_conky=true; fi
    if ! $want_ags && ! $want_conky; then
        if $USE_CONKY; then want_conky=true; else want_ags=true; fi
    fi

    case "$DISTRO_FAMILY" in
        arch)   install_deps_arch "$want_ags" "$want_conky" ;;
        fedora) install_deps_fedora "$want_ags" "$want_conky" ;;
        debian) install_deps_debian "$want_ags" "$want_conky" ;;
        suse)   install_deps_suse "$want_ags" "$want_conky" ;;
        *)      error_exit "Unsupported distribution '$DISTRO_ID' (package manager: $PKG_MANAGER). Supported: Arch, Fedora, Debian/Ubuntu, openSUSE." ;;
    esac

    if ! $DRY_RUN; then
        ensure_cmd git
        ensure_cmd zsh
        ensure_cmd python3
        if $want_ags && ! command -v ags &> /dev/null; then
            if [[ "$DISTRO_FAMILY" == "arch" ]]; then
                log_warn "ags is not installed (AUR: aylurs-gtk-shell); the widget will not start."
            else
                log_warn "ags (AGS v3 / Astal) is not in standard $PKG_MANAGER repos. Install Astal + aylurs-gtk-shell manually or re-run with --conky."
            fi
        fi
        ensure_cmd fc-cache
    fi

    log_ok "System dependencies done"
}
