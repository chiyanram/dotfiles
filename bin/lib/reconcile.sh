# shellcheck shell=bash
# Drift-detection core for `dot reconcile` (design approach B): per-domain
# adapters, sourced by dot-reconcile, dot-doctor, dot-migrate. Detection is
# read-only; the prune/adopt verbs at the bottom are invoked ONLY by dot-reconcile.
# Functions only — no side effects at source time; safe under the caller's set -e.
# Requires common.sh (classify_link, managed_targets, run_sdk) sourced first.

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

# stdin → stdout: keep only the Brewfile lines active on THIS OS. Entries in
# the other OS's `if OS.mac?` / `elsif OS.linux?` branch are not declared here
# (issue #37: a flat grep reported linux-only xclip as missing on macOS).
# Assumes the repo's Brewfile convention: one top-level OS conditional, no
# nesting — `end` closes the block.
_reconcile_brew_os_lines() {
  local os="OS.linux?"
  if [ "$(uname)" = "Darwin" ]; then os="OS.mac?"; fi
  awk -v os="$os" '
    /^[[:space:]]*if OS\./    { in_block = 1; keep = index($0, os) > 0; next }
    /^[[:space:]]*elsif OS\./ { if (in_block) { keep = index($0, os) > 0; next } }
    /^[[:space:]]*end[[:space:]]*$/ { if (in_block) { in_block = 0; next } }
    !in_block || keep { print }
  '
}

# Brewfile content on stdin → declared names: formulas canonicalized, casks as-is.
_reconcile_brew_declared_names() {
  local content
  content="$(_reconcile_brew_os_lines)"
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

# Doctor's cut of the declared set: formulas for THIS OS in their declared
# spelling, Brewfile order. No casks (a cask is an app, not a binary to probe)
# and no alias canonicalization — doctor's brew_cmd_for maps declared spellings
# (kubectl) to binaries; brew's canonical name (kubernetes-cli) would miss (#42).
reconcile_brew_declared_formulas() {
  _reconcile_brew_declared_raw | _reconcile_brew_os_lines | _reconcile_brew_names brew
}

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

# --- prune verbs (ph2, #24) ------------------------------------------------------
# One item per call; destructive. dot-reconcile is the ONLY caller and validates
# every name against the domain's undeclared set first (that check — computed
# canonical-vs-canonical via the alias map — is what guarantees a declared or
# declared-elsewhere package can never reach these). Symlinks have no prune verb:
# dangling links are `dot clean`'s job (decided, epic #22).

reconcile_brew_prune() {
  if brew list --cask 2>/dev/null | grep -qxF "$1"; then
    brew uninstall --cask "$1"
  else
    brew uninstall "$1"
  fi
}

# A candidate may hold several versions; uninstall each. `current` is SDKMAN's
# active-version symlink, not an install — skip it.
reconcile_sdkman_prune() {
  local dir="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/$1" version
  for version in "$dir"/*; do
    [ -d "$version" ] || continue
    [ -L "$version" ] && continue
    run_sdk uninstall "$1" "${version##*/}" || return 1
  done
}

reconcile_plugins_prune() {
  local zpd="${ZPLUGDIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins}"
  rm -rf "${zpd:?}/${1:?}"
  rmdir "$zpd/${1%%/*}" 2>/dev/null || true # owner dir, if now empty
}

# --- adopt verbs (ph3, #25) --------------------------------------------------------
# One item per call; appends to the declared file and leaves it UNCOMMITTED —
# the user reviews the diff and commits (the repo stays the source of truth
# without silent history). Same contract as prune: dot-reconcile is the only
# caller and has already validated the name against the undeclared set.

# Append to the active profile's Brewfile ($2 = core promotes to Brewfile.core).
# Casks are detected from the installed set; the trailing comment matches the
# Brewfile house style (every entry explains itself — this one asks the user to).
reconcile_brew_adopt() {
  local name="$1" file kind=brew
  if [ "${2:-}" = "core" ]; then
    file="$DOTFILES/brew/Brewfile.core"
  else
    file="$DOTFILES/brew/Brewfile.$(dot_profile)"
  fi
  brew list --cask 2>/dev/null | grep -qxF "$name" && kind=cask
  printf "%-38s # adopted by dot reconcile — describe me\n" "$kind '$name'" >>"$file"
}

# Tools append as a bare candidate (the toolchain's latest-stable convention).
# java pins Temurin majors: each installed *-tem version adopts as `java <major>`;
# a non-Temurin JDK (graalvm, ...) can't be expressed by resolve_temurin, so it
# is reported for by-hand adoption instead.
reconcile_sdkman_adopt() {
  local cand="$1" tc="${SDKMAN_TOOLCHAIN:-$DOTFILES/sdkman/toolchain}"
  if [ "$cand" != "java" ]; then
    printf '%s\n' "$cand" >>"$tc"
    return 0
  fi
  local dir="${SDKMAN_DIR:-$HOME/.sdkman}/candidates/java" version majors=""
  for version in "$dir"/*; do
    [ -d "$version" ] || continue
    [ -L "$version" ] && continue # `current` symlink
    version="${version##*/}"
    case "$version" in
      *-tem) majors="${majors}java ${version%%[.-]*}"$'\n' ;;
      *) log_warning "java $version is not a Temurin JDK — adopt it by hand (the toolchain pins Temurin majors)" ;;
    esac
  done
  majors="$(printf '%s' "$majors" | sort -u)"
  [ -n "$majors" ] || return 1
  printf '%s\n' "$majors" >>"$tc"
}

# Guarded .zshrc edit (the decided plugins-adopt shape, epic #22): insert
# `zfetch owner/repo` right after the LAST zfetch plugin line — the end of the
# main post-compinit group — then smoke-test the shell; on failure revert the
# edit and warn. Plugins needing pre-compinit placement or keybindings are the
# edge the user relocates before committing (the edit stays uncommitted).
reconcile_plugins_adopt() {
  local plugin="$1" zshrc="$DOTFILES/home/.zshrc" anchor backup
  anchor="$(grep -nE '^[[:space:]]*zfetch[[:space:]]+[^[:space:]]+/' "$zshrc" 2>/dev/null |
    tail -1 | cut -d: -f1)"
  if [ -z "$anchor" ]; then
    log_error "no zfetch anchor in .zshrc — add 'zfetch $plugin' by hand"
    return 1
  fi
  backup="$(mktemp)"
  cp "$zshrc" "$backup"
  awk -v n="$anchor" -v p="$plugin" \
    'NR == n { print; print "zfetch " p; next } { print }' \
    "$backup" >"$zshrc"
  if zsh -i -c 'echo ok' >/dev/null 2>&1; then
    rm -f "$backup"
    return 0
  fi
  cp "$backup" "$zshrc"
  rm -f "$backup"
  log_error "shell smoke failed after inserting zfetch $plugin — reverted .zshrc"
  return 1
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
