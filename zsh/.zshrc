# Always use the repository prompt config without interactive wizard.
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Manjaro Visuals ---
# Run fastfetch after initialization to keep Powerlevel10k instant prompt clean.
if [[ -o login ]]; then
  autoload -Uz add-zsh-hook
  _run_fastfetch_once() {
    if command -v fastfetch &> /dev/null; then
      fastfetch --logo manjaro --logo-color-1 green --logo-color-2 white
    fi
    add-zsh-hook -d precmd _run_fastfetch_once
  }
  add-zsh-hook precmd _run_fastfetch_once
fi

# Source manjaro-zsh-configuration
if [[ -e /usr/share/zsh/manjaro-zsh-config ]]; then
  source /usr/share/zsh/manjaro-zsh-config
fi

# --- Powerlevel10k ---
if [[ -r ~/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source ~/powerlevel10k/powerlevel10k.zsh-theme
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
elif [[ -e /usr/share/zsh/manjaro-zsh-prompt ]]; then
  # Fallback only when user-local powerlevel10k is unavailable.
  source /usr/share/zsh/manjaro-zsh-prompt
fi

# --- Plugins ---
[ -f ~/.zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# --- Tools ---
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# --- Sudo ESC-ESC Shortcut ---
sudo-command-line() {
    [[ -z $BUFFER ]] && zle up-history
    if [[ $BUFFER != sudo\ * ]]; then
        BUFFER="sudo $BUFFER"
        CURSOR=$(( CURSOR + 5 ))
    fi
}
zle -N sudo-command-line
bindkey "\e\e" sudo-command-line

# --- Aliases & Functions ---
alias ls="ls --color=auto"
alias grep="grep --color=auto"
alias update="pamac upgrade --aur"
alias clean="pamac clean --keep 2"
alias install="pamac install"
alias remove="pamac remove"

# --- Git Enhancements ---
alias lg="lazygit"
alias gst="git status"
alias gco="git checkout"
alias gcm="git commit -m"
alias ga="git add"
alias gp="git push"
alias gl="git pull"
alias glog="git log --oneline --graph --decorate"
alias gd="git diff"

# Use delta for diffs if available
if command -v delta &> /dev/null; then
    export GIT_PAGER="delta"
fi

# Custom path
export PATH=$PATH:$HOME/.local/bin
