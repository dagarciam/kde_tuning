# Always use the repository prompt config without interactive wizard.
typeset -g POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Distro Visuals ---
# Run fastfetch after initialization to keep Powerlevel10k instant prompt clean.
if [[ -o login ]]; then
  autoload -Uz add-zsh-hook
  _run_fastfetch_once() {
    if command -v fastfetch &> /dev/null; then
      if [[ -r /etc/os-release ]] && grep -qi '^ID=manjaro' /etc/os-release; then
        fastfetch --logo manjaro --logo-color-1 green --logo-color-2 white
      else
        fastfetch
      fi
    fi
    add-zsh-hook -d precmd _run_fastfetch_once
  }
  add-zsh-hook precmd _run_fastfetch_once
fi

# --- History & Shell Options ---
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS
setopt AUTO_CD INTERACTIVE_COMMENTS

# --- Extra Completions (before compinit) ---
if [[ -d ~/.zsh-plugins/zsh-completions/src ]]; then
  fpath=(~/.zsh-plugins/zsh-completions/src $fpath)
fi

# Source manjaro-zsh-configuration
if [[ -e /usr/share/zsh/manjaro-zsh-config ]]; then
  source /usr/share/zsh/manjaro-zsh-config
fi

# Initialize completion system with daily cache when not already loaded
if (( ! $+functions[compdef] )); then
  autoload -Uz compinit
  if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
    compinit
  else
    compinit -C
  fi
fi

# Completion styling (case-insensitive + colors)
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' menu no
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always -1 $realpath 2>/dev/null'
zstyle ':fzf-tab:complete:z:*' fzf-preview 'ls --color=always -1 $realpath 2>/dev/null'
zstyle ':fzf-tab:*' switch-group '<' '>'

# --- Powerlevel10k ---
if [[ -r ~/powerlevel10k/powerlevel10k.zsh-theme ]]; then
  source ~/powerlevel10k/powerlevel10k.zsh-theme
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
elif [[ -e /usr/share/zsh/manjaro-zsh-prompt ]]; then
  # Fallback only when user-local powerlevel10k is unavailable.
  source /usr/share/zsh/manjaro-zsh-prompt
fi

# --- Plugins (order matters: fzf-tab -> autosuggestions/autopair/ysu -> syntax highlighting -> history-substring-search) ---
[[ -f ~/.zsh-plugins/fzf-tab/fzf-tab.plugin.zsh ]] && source ~/.zsh-plugins/fzf-tab/fzf-tab.plugin.zsh

if [[ -f ~/.zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  source ~/.zsh-plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

[[ -f ~/.zsh-plugins/zsh-autopair/autopair.zsh ]] && source ~/.zsh-plugins/zsh-autopair/autopair.zsh

if [[ -f ~/.zsh-plugins/zsh-you-should-use/you-should-use.plugin.zsh ]]; then
  export YSU_MESSAGE_POSITION="after"
  source ~/.zsh-plugins/zsh-you-should-use/you-should-use.plugin.zsh
fi

if [[ -f ~/.zsh-plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]]; then
  source ~/.zsh-plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
elif [[ -f ~/.zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source ~/.zsh-plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [[ -f ~/.zsh-plugins/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source ~/.zsh-plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  [[ -n "${terminfo[kcuu1]:-}" ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up
  [[ -n "${terminfo[kcud1]:-}" ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down
fi

# --- Tools ---
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

if [[ -f ~/.fzf.zsh ]]; then
    source ~/.fzf.zsh
elif [[ -f /usr/share/fzf/shell/key-bindings.zsh ]]; then
    source /usr/share/fzf/shell/key-bindings.zsh
elif [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
fi

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
if command -v pamac &> /dev/null; then
    alias update="pamac upgrade --aur"
    alias clean="pamac clean --keep 2"
    alias install="pamac install"
    alias remove="pamac remove"
elif command -v paru &> /dev/null; then
    alias update="paru -Syu"
    alias clean="paru -Sc"
    alias install="paru -S"
    alias remove="paru -Rns"
elif command -v yay &> /dev/null; then
    alias update="yay -Syu"
    alias clean="yay -Sc"
    alias install="yay -S"
    alias remove="yay -Rns"
elif command -v pacman &> /dev/null; then
    alias update="sudo pacman -Syu"
    alias clean="sudo pacman -Sc"
    alias install="sudo pacman -S"
    alias remove="sudo pacman -Rns"
elif command -v dnf &> /dev/null; then
    alias update="sudo dnf upgrade --refresh"
    alias clean="sudo dnf autoremove && sudo dnf clean all"
    alias install="sudo dnf install"
    alias remove="sudo dnf remove"
elif command -v apt &> /dev/null; then
    alias update="sudo apt update && sudo apt upgrade"
    alias clean="sudo apt autoremove && sudo apt autoclean"
    alias install="sudo apt install"
    alias remove="sudo apt remove"
elif command -v zypper &> /dev/null; then
    alias update="sudo zypper dup"
    alias clean="sudo zypper clean --all"
    alias install="sudo zypper install"
    alias remove="sudo zypper remove"
fi

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
