export ZSH=$DOTFILES/zsh

# Profiler (activate with: touch ~/.zshrc.profiler)
if [[ -f "$HOME/.zshrc.profiler" ]]; then
    zmodload zsh/datetime
    setopt PROMPT_SUBST
    PS4='+$EPOCHREALTIME %N:%i> '
    zshrc_profiler_logfile=$TMPDIR/zshrc_profiler.$$.log
    echo "Profiling to $zshrc_profiler_logfile"
    exec 3>&2 2>$zshrc_profiler_logfile
    setopt XTRACE
fi

# Source functions early
source "$ZDOTDIR/.zsh_functions"

########################################################
# Core Configuration
########################################################

# Homebrew completions (before compinit)
if type brew &>/dev/null; then
    FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi

# Initialize autocomplete with 24h caching
autoload -U compinit add-zsh-hook
if [[ -n "${ZDOTDIR:-${HOME}}"/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# PATH setup (consolidated)
export PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
export PATH="/usr/local/sbin:$PATH"
export PATH="$DOTFILES/bin:$PATH"
export PATH="$HOME/bin:$PATH"
export PATH="/Applications/IntelliJ IDEA.app/Contents/MacOS:$PATH"

# De-duplicate PATH
typeset -U path

# Core directories
export CODE_DIR=~/Workspaces

# Shell behavior
export REPORTTIME=10
export KEYTIMEOUT=1

setopt NO_BG_NICE
setopt NO_HUP
setopt NO_LIST_BEEP
setopt LOCAL_OPTIONS
setopt LOCAL_TRAPS
setopt PROMPT_SUBST
setopt COMPLETE_ALIASES

# History settings
setopt EXTENDED_HISTORY
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt INC_APPEND_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST

########################################################
# Key Bindings
########################################################

# Navigation
bindkey "^[[1;5C" forward-word                    # Ctrl-right
bindkey "^[[1;5D" backward-word                   # Ctrl-left
bindkey '^[^[[C' forward-word                     # Ctrl-right (alt)
bindkey '^[^[[D' backward-word                    # Ctrl-left (alt)
bindkey '^[[1;3D' beginning-of-line               # Alt-left
bindkey '^[[1;3C' end-of-line                     # Alt-right
bindkey '^[[5D' beginning-of-line                 # Alt-left (alt)
bindkey '^[[5C' end-of-line                       # Alt-right (alt)
bindkey '^?' backward-delete-char                 # Backspace

# Delete key handling
if [[ "${terminfo[kdch1]}" != "" ]]; then
    bindkey "${terminfo[kdch1]}" delete-char
else
    bindkey "^[[3~" delete-char
    bindkey "^[3;5~" delete-char
    bindkey "\e[3~" delete-char
fi

# Vi-mode bindings
bindkey "^A" vi-beginning-of-line
bindkey -M viins "^F" vi-forward-word
bindkey -M viins "^E" vi-add-eol
bindkey "^J" history-beginning-search-forward
bindkey "^K" history-beginning-search-backward

########################################################
# Completion Settings
########################################################

zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' insert-tab pending
zstyle ':completion:*' completer _expand _complete _files _correct _approximate
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*' group-name ''

########################################################
# Plugin Management
########################################################

export ZPLUGDIR="$CACHEDIR/zsh/plugins"
[[ -d "$ZPLUGDIR" ]] || mkdir -p "$ZPLUGDIR"
typeset -A plugins

# Load plugins
zfetch zsh-users/zsh-syntax-highlighting
zfetch zsh-users/zsh-autosuggestions
zfetch grigorii-zander/zsh-npm-scripts-autocomplete
zfetch Aloxaf/fzf-tab

########################################################
# Tool Initialization
########################################################

# Node Version Manager (choose ONE - fnm is faster)
if [[ -x "$(command -v fnm)" ]]; then
    eval "$(fnm env --use-on-cd)"
elif [[ -s "/opt/homebrew/opt/nvm/nvm.sh" ]]; then
    export NVM_DIR="$HOME/.nvm"
    source "/opt/homebrew/opt/nvm/nvm.sh"
    [[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ]] && source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
fi

# Python
if [[ -x "$(command -v pyenv)" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi

# PNPM
if [[ -x "$(command -v pnpm)" ]]; then
    export PNPM_HOME="$HOME/Library/pnpm"
    case ":$PATH:" in
        *":$PNPM_HOME:"*) ;;
        *) export PATH="$PNPM_HOME:$PATH" ;;
    esac
fi

# Directory Navigation (choose ONE - zoxide is better)
if [[ -x "$(command -v zoxide)" ]]; then
    eval "$(zoxide init zsh)"  # REMOVED --hook pwd (this was your problem)
elif [[ -f "$(brew --prefix)/etc/profile.d/z.sh" ]]; then
    source "$(brew --prefix)/etc/profile.d/z.sh"
fi

# FZF
if [[ -x "$(command -v fzf)" ]]; then
    export FZF_DEFAULT_COMMAND='fd --type f'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_DEFAULT_OPTS="--color bg:-1,bg+:-1,fg:-1,fg+:#feffff,hl:#993f84,hl+:#d256b5,info:#676767,prompt:#676767,pointer:#676767"
    source <(fzf --zsh)
fi

########################################################
# Visual Enhancements
########################################################

# Colored man pages
export MANROFFOPT='-c'
export LESS_TERMCAP_mb=$(tput bold; tput setaf 2)
export LESS_TERMCAP_md=$(tput bold; tput setaf 6)
export LESS_TERMCAP_me=$(tput sgr0)
export LESS_TERMCAP_so=$(tput bold; tput setaf 3; tput setab 4)
export LESS_TERMCAP_se=$(tput rmso; tput sgr0)
export LESS_TERMCAP_us=$(tput smul; tput bold; tput setaf 7)
export LESS_TERMCAP_ue=$(tput rmul; tput sgr0)
export LESS_TERMCAP_mr=$(tput rev)
export LESS_TERMCAP_mh=$(tput dim)

# LS colors
if ls --color > /dev/null 2>&1; then
    colorflag="--color"
else
    colorflag="-G"
fi

# Terminal info
[[ -e ~/.terminfo ]] && export TERMINFO_DIRS=~/.terminfo:/usr/share/terminfo

########################################################
# Load Custom Files
########################################################

# Load local configurations
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
[[ -f ~/.localrc ]] && source ~/.localrc

# Load modular config files
for file in "$ZDOTDIR/.zsh_aliases" "$ZDOTDIR/.docker_aliases"; do
    [[ -f "$file" ]] && source "$file"
done

########################################################
# Tool-Specific Setup (Keep at End)
########################################################

# Docker completions
if [[ -d "$HOME/.docker/completions" ]]; then
    fpath=($HOME/.docker/completions $fpath)
fi

# SDKMAN (must be at end)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

# Maven daemon completion
[[ -n "$MVND_HOME" && -f "$MVND_HOME/bin/mvnd-bash-completion.bash" ]] && source "$MVND_HOME/bin/mvnd-bash-completion.bash"

# Prompt (initialize last)
if [[ -x "$(command -v starship)" ]]; then
    eval "$(starship init zsh)"
fi

# Profiler stop
if [[ -f "$HOME/.zshrc.profiler" ]]; then
    unsetopt XTRACE
    exec 2>&3 3>&-
    echo ".zshrc profiling complete. View with: zshrc_profiler_view"
fi