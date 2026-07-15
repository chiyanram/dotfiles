# .zprofile is sourced on login shells and before .zshrc. As a general rule, it should not change the
# shell environment at all.

if [[ -f /opt/homebrew/bin/brew ]]; then
    # Homebrew exists at /opt/homebrew for arm64 macos
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    # or at /usr/local for intel macos
    eval "$(/usr/local/bin/brew shellenv)"
fi

# JetBrains Toolbox scripts (CLI launchers for installed IDEs)
if [[ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]]; then
    export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
fi

# Machine-specific login-shell env (installer PATH writes, per-host tweaks) —
# not committed. The sink for drift an installer would otherwise append here.
[[ -f ~/.zprofile.local ]] && source ~/.zprofile.local
