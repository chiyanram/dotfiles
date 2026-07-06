# shellcheck shell=bash
# Read-only drift-detection core for `dot reconcile` (design approach B):
# per-domain adapters, sourced by dot-reconcile, dot-doctor, dot-migrate.
# Functions only — no side effects at source time; safe under the caller's set -e.

# --- plugins domain -----------------------------------------------------------
# zfetch clones each `zfetch owner/repo ...` line in the repo's .zshrc to
# $ZPLUGDIR/owner/repo. Declared = those owner/repo names; actual = the cloned
# owner/repo dirs; undeclared = clones the .zshrc no longer lists (issue #20).

# Declared: owner/repo of each `zfetch owner/repo` line (skip the update/ls subcommands).
reconcile_plugins_declared() {
  local zshrc="${1:-$DOTFILES/home/.zshrc}"
  [ -f "$zshrc" ] || return 0
  grep -E '^[[:space:]]*zfetch[[:space:]]' "$zshrc" 2>/dev/null |
    awk '{print $2}' | grep -vxE 'update|ls' || true
}

# Actual: each owner/repo directory cloned under $ZPLUGDIR.
reconcile_plugins_actual() {
  local zpd="${ZPLUGDIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins}"
  [ -d "$zpd" ] || return 0
  find "$zpd" -mindepth 2 -maxdepth 2 -type d 2>/dev/null |
    sed "s|^${zpd%/}/||"
}

# Undeclared: actual clones the repo no longer declares.
reconcile_plugins_undeclared() {
  local declared
  declared="$(reconcile_plugins_declared)"
  reconcile_plugins_actual |
    grep -vxF -f <(printf '%s\n' "$declared") 2>/dev/null || true
}
