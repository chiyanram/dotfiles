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

# --- brew domain --------------------------------------------------------------
# Declared = brew/cask names in the active profile's Brewfiles (core + <profile>)
# plus the config-driven docker-runtime cask. "Declared elsewhere" = names in
# another profile's Brewfile (reported, never pruned). Actual = brew leaves +
# installed casks. Undeclared = actual minus declared minus declared-elsewhere.

# Extract brew/cask package names from Brewfile content on stdin.
_reconcile_brew_names() {
  grep -E "^[[:space:]]*(brew|cask) '[^']+'" 2>/dev/null |
    sed -E "s/^[[:space:]]*(brew|cask) '([^']+)'.*/\2/" || true
}

# Raw declared content: the active profile's Brewfiles + the docker-runtime cask.
_reconcile_brew_declared_raw() {
  local f
  while IFS= read -r f; do [ -f "$f" ] && cat "$f"; done < <(dot_brewfiles)
  dot_docker_runtime_entries "$(dot_docker_runtime)" 2>/dev/null || true
}

reconcile_brew_declared() { _reconcile_brew_declared_raw | _reconcile_brew_names | sort -u; }

reconcile_brew_declared_elsewhere() {
  local active other dir="$DOTFILES/brew"
  active="$(dot_profile)"
  for other in personal work; do
    [ "$other" = "$active" ] && continue
    [ -f "$dir/Brewfile.$other" ] && cat "$dir/Brewfile.$other"
  done | _reconcile_brew_names | sort -u
}

reconcile_brew_actual() {
  {
    brew leaves 2>/dev/null
    brew list --cask 2>/dev/null
  } | sort -u
}

reconcile_brew_undeclared() {
  local excluded
  excluded="$(
    reconcile_brew_declared
    reconcile_brew_declared_elsewhere
  )"
  reconcile_brew_actual |
    grep -vxF -f <(printf '%s\n' "$excluded") 2>/dev/null || true
}
