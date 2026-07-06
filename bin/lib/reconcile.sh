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
  local zshrc="$DOTFILES/home/.zshrc"
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

# Extract package names of one kind ($1 = brew|cask) from Brewfile content on stdin.
_reconcile_brew_names() {
  grep -E "^[[:space:]]*$1 '[^']+'" 2>/dev/null |
    sed -E "s/^[[:space:]]*$1 '([^']+)'.*/\1/" || true
}

# Formula name-alias map, one "alias|canonical" line per alias (issue #26).
# Brewfiles may declare a formula by an alias (kubectl) while brew installs and
# lists the canonical name (kubernetes-cli); set-diffing the two spellings
# reports a false missing+undeclared pair — and --prune (ph2) must never offer
# to uninstall a package that IS declared, just under an alias.
# Sources, cheapest first (filesystem reads, no per-package brew calls):
#   1. Homebrew's API cache (the default install-from-API world);
#   2. a locally tapped homebrew-core (HOMEBREW_NO_INSTALL_FROM_API setups):
#      Aliases/<alias> symlinks to the canonical <formula>.rb.
# Neither present (day-0, CI): emit nothing — names pass through unnormalized,
# which is the pre-#26 behavior.
_reconcile_brew_alias_map() {
  local cache="${HOMEBREW_CACHE:-$HOME/Library/Caches/Homebrew}/api/formula_aliases.txt"
  if [ -f "$cache" ]; then
    cat "$cache"
    return 0
  fi
  command -v brew >/dev/null 2>&1 || return 0
  local dir link
  dir="$(brew --repository 2>/dev/null)/Library/Taps/homebrew/homebrew-core/Aliases"
  [ -d "$dir" ] || return 0
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    printf '%s|%s\n' "${link##*/}" "$(basename "$(readlink "$link")" .rb)"
  done
}

# stdin → stdout: rewrite each formula alias to its canonical name. Applied to
# BOTH sides of every brew set-diff so comparisons are canonical-vs-canonical.
# Formula names only — cask tokens have no alias namespace and must never be
# rewritten by a colliding formula alias.
_reconcile_brew_canonical() {
  local map
  map="$(_reconcile_brew_alias_map)"
  if [ -z "$map" ]; then
    cat
    return 0
  fi
  # NR==FNR reads the (guaranteed non-empty) map first, then filters stdin.
  awk -F'|' '
    NR == FNR { canon[$1] = $2; next }
    { if ($0 in canon) print canon[$0]; else print }
  ' <(printf '%s\n' "$map") -
}

# Brewfile content on stdin → declared names: formulas canonicalized, casks as-is.
_reconcile_brew_declared_names() {
  local content
  content="$(cat)"
  printf '%s\n' "$content" | _reconcile_brew_names brew | _reconcile_brew_canonical
  printf '%s\n' "$content" | _reconcile_brew_names cask
}

# Raw declared content: the active profile's Brewfiles + the docker-runtime cask.
_reconcile_brew_declared_raw() {
  local f
  while IFS= read -r f; do [ -f "$f" ] && cat "$f"; done < <(dot_brewfiles)
  dot_docker_runtime_entries "$(dot_docker_runtime)" 2>/dev/null || true
}

reconcile_brew_declared() { _reconcile_brew_declared_raw | _reconcile_brew_declared_names | sort -u; }

reconcile_brew_declared_elsewhere() {
  local active other dir="$DOTFILES/brew"
  active="$(dot_profile)"
  for other in personal work; do
    # guard-clause continues: a trailing failed `[ ... ] && cmd` would make the
    # loop (and via pipefail, the pipeline) exit non-zero under callers' set -e
    [ "$other" = "$active" ] && continue
    [ -f "$dir/Brewfile.$other" ] || continue
    cat "$dir/Brewfile.$other"
  done | _reconcile_brew_declared_names | sort -u
}

reconcile_brew_actual() {
  {
    brew leaves 2>/dev/null | _reconcile_brew_canonical
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

# Missing = declared but not installed. Diff against `brew list` (ALL installed),
# not `leaves`: a declared formula that is also some other formula's dependency
# isn't a leaf, and must not be reported as missing.
reconcile_brew_missing() {
  local installed
  installed="$(
    brew list --formula 2>/dev/null | _reconcile_brew_canonical
    brew list --cask 2>/dev/null
  )"
  reconcile_brew_declared |
    grep -vxF -f <(printf '%s\n' "$installed") 2>/dev/null || true
}

# --- sdkman domain ------------------------------------------------------------
# Declared = candidates named in sdkman/toolchain; actual = installed candidate
# dirs under $SDKMAN_DIR/candidates. Undeclared = installed candidates the
# toolchain doesn't declare (e.g. an ad-hoc `sdk install scala`). Version-level
# java drift (an installed java the toolchain doesn't pin) is a deferred
# refinement — this is candidate-level.

reconcile_sdkman_declared() {
  local tc="${SDKMAN_TOOLCHAIN:-$DOTFILES/sdkman/toolchain}"
  [ -f "$tc" ] || return 0
  sed 's/#.*//' "$tc" | awk 'NF {print $1}' | sort -u
}

reconcile_sdkman_actual() {
  local dir="${SDKMAN_DIR:-$HOME/.sdkman}/candidates"
  [ -d "$dir" ] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
    sed "s|^${dir%/}/||" | sort -u
}

reconcile_sdkman_undeclared() {
  local declared
  declared="$(reconcile_sdkman_declared)"
  reconcile_sdkman_actual |
    grep -vxF -f <(printf '%s\n' "$declared") 2>/dev/null || true
}

reconcile_sdkman_missing() {
  local actual
  actual="$(reconcile_sdkman_actual)"
  reconcile_sdkman_declared |
    grep -vxF -f <(printf '%s\n' "$actual") 2>/dev/null || true
}

reconcile_plugins_missing() {
  local actual
  actual="$(reconcile_plugins_actual)"
  reconcile_plugins_declared |
    grep -vxF -f <(printf '%s\n' "$actual") 2>/dev/null || true
}

# --- symlinks domain (report-only) ---------------------------------------------
# Requires common.sh (classify_link, managed_targets) to be sourced first.
# No prune/adopt verbs: remediation is the existing `dot clean` / `dot link`.

# Declared-but-unhealthy managed links: "<state>\t<label>" for every managed
# target whose state isn't ok (missing / wrong / real).
reconcile_symlinks_missing() {
  local source target label state
  while IFS=$'\t' read -r source target label; do
    state=$(classify_link "$source" "$target")
    [ "$state" = "ok" ] && continue
    printf '%s\t%s\n' "$state" "$label"
  done < <(managed_targets)
}

# Dangling links whose repo source was deleted — emitted as ABSOLUTE paths so
# `dot clean` can rm them directly (the report prettifies to ~/). Two scans:
#  (a) $XDG_CONFIG_HOME depth-1 links into $DOTFILES that no longer resolve
#      (removed config packages);
#  (b) home-file targets derived from GIT HISTORY of deleted home/ files —
#      current repo files can't name them (the source is gone), which is exactly
#      why a repo-derived scan misses the ~/.claude case (#21).
reconcile_symlinks_dangling() {
  local config_home="${CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"
  {
    local link
    if [ -d "$config_home" ]; then
      while IFS= read -r -d '' link; do
        if [ ! -e "$link" ] && [[ "$(readlink "$link")" == "$DOTFILES"* ]]; then
          printf '%s\n' "$link"
        fi
      done < <(find "$config_home" -maxdepth 1 -type l -print0 2>/dev/null || true)
    fi

    local rel target
    if git -C "$DOTFILES" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        target="$HOME/${rel#home/}"
        if [ -L "$target" ] && [ ! -e "$target" ] &&
          [[ "$(readlink "$target")" == "$DOTFILES"* ]]; then
          printf '%s\n' "$target"
        fi
      done < <(git -C "$DOTFILES" log --diff-filter=D --name-only --pretty=format: -- home/ 2>/dev/null | sort -u)
    fi
  } | sort -u
}

# --- summary --------------------------------------------------------------------
# One line per domain that has drift ("<domain>: N undeclared, M missing"), empty
# when everything converges. For dot-doctor / dot-migrate to surface cheaply.

_reconcile_count() { grep -c . 2>/dev/null || true; }

reconcile_summary() {
  local domain undeclared missing
  for domain in brew sdkman plugins symlinks; do
    if [ "$domain" = "symlinks" ]; then
      undeclared="$(reconcile_symlinks_dangling | _reconcile_count)"
      missing="$(reconcile_symlinks_missing | _reconcile_count)"
    else
      undeclared="$("reconcile_${domain}_undeclared" | _reconcile_count)"
      missing="$("reconcile_${domain}_missing" | _reconcile_count)"
    fi
    [ "$((undeclared + missing))" -eq 0 ] && continue
    printf '%s: %s undeclared, %s missing\n' "$domain" "$undeclared" "$missing"
  done
}
