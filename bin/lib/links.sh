#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

########################################################
# Link resolver
########################################################
# Shared by `dot link` (plan/apply/status) and `dot reconcile` (symlink drift),
# so preview, action, and drift report never disagree on a link's state.

# classify_link <source> <target> — ok | wrong | real | missing
classify_link() {
  local source="$1"
  local target="$2"
  if [ -L "$target" ]; then
    local actual
    actual=$(readlink "$target")
    if [ "$actual" = "$source" ]; then
      echo "ok"
    else
      echo "wrong"
    fi
  elif [ -e "$target" ]; then
    echo "real"
  else
    echo "missing"
  fi
}

# managed_targets [config|home] — emit "<source>\t<target>\t<label>" for every
# managed target: config packages (config/<pkg> → ~/.config/<pkg>) and home
# files (home/<rel> → ~/<rel>); the optional kind emits just that slice. Single
# source of truth for "what dot link manages", so the plan and the action agree.
managed_targets() {
  local kind="${1:-all}"
  case "$kind" in all | config | home) ;; *)
    log_error "managed_targets: unknown kind '$kind' (config|home)"
    return 1
    ;;
  esac
  local config_home="${CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"
  local config name file rel
  if [ "$kind" != "home" ]; then
    for config in "$DOTFILES/config"/*; do
      [ -d "$config" ] || continue
      # skip empty config packages (nothing to link)
      [[ -n "$(ls -A "$config" 2>/dev/null)" ]] || continue
      name=$(basename "$config")
      printf '%s\t%s\t~/.config/%s\n' "$config" "$config_home/$name" "$name"
    done
  fi
  [ "$kind" = "config" ] && return 0
  [ -d "$DOTFILES/home" ] || return 0
  while IFS= read -r -d '' file; do
    rel="${file#"$DOTFILES"/home/}"
    printf '%s\t%s\t~/%s\n' "$file" "$HOME/$rel" "$rel"
  done < <(find "$DOTFILES/home" -type f -print0)
}
