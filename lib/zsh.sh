#!/bin/bash
# ==============================================================================
# lib/zsh.sh - Zsh shell configuration, Powerlevel10k, and default shell setup
# ==============================================================================

[[ -n "${_LIB_ZSH_LOADED:-}" ]] && return 0
_LIB_ZSH_LOADED=1

setup_zsh() {
    log_progress "$1" "$2" "Applying Zsh & Powerlevel10k config"
    ensure_file "$REPO_DIR/zsh/.zshrc"
    ensure_file "$REPO_DIR/zsh/.p10k.zsh"

    if $DRY_RUN; then
        log_dry "backup + cp .zshrc and .p10k.zsh to $REAL_HOME"
    else
        [[ -f "$REAL_HOME/.zshrc" ]] && cp "$REAL_HOME/.zshrc" "$REAL_HOME/.zshrc.bak"
        [[ -f "$REAL_HOME/.p10k.zsh" ]] && cp "$REAL_HOME/.p10k.zsh" "$REAL_HOME/.p10k.zsh.bak"
        cp "$REPO_DIR"/zsh/.zshrc "$REAL_HOME/.zshrc"
        cp "$REPO_DIR"/zsh/.p10k.zsh "$REAL_HOME/.p10k.zsh"
    fi

    # Set Zsh as default user shell if not already configured
    local zsh_bin
    zsh_bin="$(command -v zsh 2>/dev/null || which zsh 2>/dev/null || echo "/bin/zsh")"
    local current_user_shell
    current_user_shell="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f7)"

    local current_shell_real=""
    local zsh_bin_real=""
    [[ -n "$current_user_shell" ]] && current_shell_real="$(realpath "$current_user_shell" 2>/dev/null || echo "$current_user_shell")"
    [[ -n "$zsh_bin" ]] && zsh_bin_real="$(realpath "$zsh_bin" 2>/dev/null || echo "$zsh_bin")"

    if [[ -x "$zsh_bin" && -n "$current_shell_real" && "$current_shell_real" != "$zsh_bin_real" ]]; then
        if $DRY_RUN; then
            log_dry "Would set default shell for user '$REAL_USER' to $zsh_bin"
        else
            log_info "Setting default login shell for '$REAL_USER' to $zsh_bin..."
            local changed=false
            if command -v chsh &>/dev/null; then
                if run_as_root chsh -s "$zsh_bin" "$REAL_USER" 2>/dev/null; then
                    changed=true
                elif chsh -s "$zsh_bin" 2>/dev/null; then
                    changed=true
                fi
            fi
            if ! $changed && command -v usermod &>/dev/null; then
                if run_as_root usermod -s "$zsh_bin" "$REAL_USER" 2>/dev/null; then
                    changed=true
                fi
            fi

            local new_shell
            new_shell="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f7)"
            local new_shell_real=""
            [[ -n "$new_shell" ]] && new_shell_real="$(realpath "$new_shell" 2>/dev/null || echo "$new_shell")"

            if [[ "$new_shell_real" == "$zsh_bin_real" ]]; then
                log_ok "Default shell for user '$REAL_USER' set to $zsh_bin"
            else
                log_warn "Could not change default shell automatically. You can run manually: chsh -s $zsh_bin"
            fi
        fi
    else
        log_info "Default shell for user '$REAL_USER' is already $zsh_bin"
    fi

    log_ok "Zsh configuration applied"
}
